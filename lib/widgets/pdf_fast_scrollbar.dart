import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

/// An auto-hiding vertical fast scrollbar thumb attached to the screen edge
/// that displays only the current page number.
class PdfFastScrollbar extends StatefulWidget {
  final pdfrx.PdfViewerController controller;
  final ValueChanged<int>? onPageScrubbed;
  final double topPadding;
  final double bottomPadding;

  const PdfFastScrollbar({
    super.key,
    required this.controller,
    this.onPageScrubbed,
    this.topPadding = 12.0,
    this.bottomPadding = 12.0,
  });

  /// Binary-searches sorted [pageLayouts] to find the 1-based page number at [docY].
  @visibleForTesting
  static int findPageAtDocumentY(List<Rect> pageLayouts, double docY) {
    if (pageLayouts.isEmpty) return 1;
    if (docY <= pageLayouts.first.bottom) return 1;
    if (docY >= pageLayouts.last.top) return pageLayouts.length;

    int low = 0;
    int high = pageLayouts.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final rect = pageLayouts[mid];
      if (docY < rect.top) {
        high = mid - 1;
      } else if (docY > rect.bottom) {
        low = mid + 1;
      } else {
        return mid + 1;
      }
    }
    final upperIdx = low.clamp(0, pageLayouts.length - 1);
    final lowerIdx = (low - 1).clamp(0, pageLayouts.length - 1);
    final distToLower = (docY - pageLayouts[lowerIdx].bottom).abs();
    final distToUpper = (pageLayouts[upperIdx].top - docY).abs();
    return (distToLower <= distToUpper ? lowerIdx : upperIdx) + 1;
  }

  /// Computes normalized scroll fraction and thumb screen Y coordinate.
  @visibleForTesting
  static ({double fraction, double thumbTop, double maxThumbTravel})? computeThumbMetrics({
    required double viewportHeight,
    required double docHeight,
    required Rect visibleRect,
    double topPadding = 12.0,
    double bottomPadding = 12.0,
    double thumbHitHeight = 36.0,
  }) {
    final maxDocScrollY = docHeight - visibleRect.height;
    if (maxDocScrollY <= 1.0 || viewportHeight <= topPadding + bottomPadding + thumbHitHeight) {
      return null;
    }
    final maxThumbTravel = viewportHeight - topPadding - bottomPadding - thumbHitHeight;
    final fraction = (visibleRect.top / maxDocScrollY).clamp(0.0, 1.0);
    final thumbTop = topPadding + fraction * maxThumbTravel;
    return (
      fraction: fraction,
      thumbTop: thumbTop,
      maxThumbTravel: maxThumbTravel,
    );
  }

  @override
  State<PdfFastScrollbar> createState() => PdfFastScrollbarState();
}

class PdfFastScrollbarState extends State<PdfFastScrollbar> {
  static const double _edgeRevealStripWidth = 20.0;
  static const double _thumbHitHeight = 36.0;
  static const Duration _autoHideDelay = Duration(milliseconds: 1800);

  bool _isVisible = false;
  bool _isDragging = false;
  double _dragStartGlobalY = 0.0;
  double _dragStartThumbTravelY = 0.0;
  double? _lastObservedDocTop;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    if (widget.controller.isReady) {
      _lastObservedDocTop = widget.controller.visibleRect.top;
    }
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant PdfFastScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _lastObservedDocTop = widget.controller.isReady ? widget.controller.visibleRect.top : null;
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// Reveals the scrollbar thumb and schedules auto-hide after [_autoHideDelay].
  void reveal({bool withHaptic = false}) {
    if (!mounted || !widget.controller.isReady) return;
    if (widget.controller.layout.pageLayouts.length <= 1) return;
    if (withHaptic && !_isVisible) {
      HapticFeedback.selectionClick();
    }
    if (!_isVisible) {
      setState(() {
        _isVisible = true;
      });
    }
    _scheduleAutoHide();
  }

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHideDelay, () {
      if (mounted && !_isDragging && _isVisible) {
        setState(() {
          _isVisible = false;
        });
      }
    });
  }

  void _onControllerChanged() {
    if (!mounted || !widget.controller.isReady) return;
    final currentDocTop = widget.controller.visibleRect.top;
    final prevDocTop = _lastObservedDocTop;
    _lastObservedDocTop = currentDocTop;

    if (prevDocTop != null && (currentDocTop - prevDocTop).abs() > 0.5) {
      _isVisible = true;
      _scheduleAutoHide();
    }
    if (_isVisible || _isDragging) {
      setState(() {});
    }
  }

  void _scrubToFraction(double fraction) {
    if (!widget.controller.isReady) return;
    final layout = widget.controller.layout;
    final visibleRect = widget.controller.visibleRect;
    final maxDocScrollY = layout.documentSize.height - visibleRect.height;
    if (maxDocScrollY <= 0) return;

    final clampedFraction = fraction.clamp(0.0, 1.0);
    final targetDocTop = clampedFraction * maxDocScrollY;
    widget.controller.goToPosition(
      documentOffset: Offset(visibleRect.left, targetDocTop),
      zoom: widget.controller.currentZoom,
      duration: Duration.zero,
    );

    final probeY = clampedFraction <= 0.001
        ? 0.0
        : (clampedFraction >= 0.999
            ? layout.documentSize.height
            : targetDocTop + visibleRect.height * 0.35);
    final page = PdfFastScrollbar.findPageAtDocumentY(layout.pageLayouts, probeY);
    widget.onPageScrubbed?.call(page);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isReady) {
      return const SizedBox.shrink();
    }
    final layout = widget.controller.layout;
    final totalPages = layout.pageLayouts.length;
    if (totalPages <= 1) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight;
        final visibleRect = widget.controller.visibleRect;
        final metrics = PdfFastScrollbar.computeThumbMetrics(
          viewportHeight: viewportHeight,
          docHeight: layout.documentSize.height,
          visibleRect: visibleRect,
          topPadding: widget.topPadding,
          bottomPadding: widget.bottomPadding,
          thumbHitHeight: _thumbHitHeight,
        );
        if (metrics == null) {
          return const SizedBox.shrink();
        }

        final showControls = _isVisible || _isDragging;
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        const activeAccent = Color(0xFF1E90FF);

        final probeY = metrics.fraction <= 0.001
            ? 0.0
            : (metrics.fraction >= 0.999
                ? layout.documentSize.height
                : visibleRect.top + visibleRect.height * 0.35);
        final displayPage = _isDragging
            ? PdfFastScrollbar.findPageAtDocumentY(layout.pageLayouts, probeY)
            : (widget.controller.pageNumber ??
                PdfFastScrollbar.findPageAtDocumentY(layout.pageLayouts, probeY));

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Slim right-edge tap zone to reveal the scrollbar on a light edge tap
            if (!showControls)
              Positioned(
                right: 0,
                top: widget.topPadding,
                bottom: widget.bottomPadding,
                width: _edgeRevealStripWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => reveal(withHaptic: true),
                ),
              ),

            // Edge-snapped simple scroll thumb displaying only the current page number
            Positioned(
              right: 0,
              top: metrics.thumbTop,
              child: IgnorePointer(
                ignoring: !showControls,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _scheduleAutoHide,
                  onVerticalDragStart: (details) {
                    _hideTimer?.cancel();
                    HapticFeedback.selectionClick();
                    setState(() {
                      _isDragging = true;
                      _isVisible = true;
                      _dragStartGlobalY = details.globalPosition.dy;
                      _dragStartThumbTravelY = metrics.fraction * metrics.maxThumbTravel;
                    });
                  },
                  onVerticalDragUpdate: (details) {
                    final deltaY = details.globalPosition.dy - _dragStartGlobalY;
                    final nextTravelY =
                        (_dragStartThumbTravelY + deltaY).clamp(0.0, metrics.maxThumbTravel);
                    _scrubToFraction(nextTravelY / metrics.maxThumbTravel);
                  },
                  onVerticalDragEnd: (_) {
                    setState(() {
                      _isDragging = false;
                    });
                    _scheduleAutoHide();
                  },
                  onVerticalDragCancel: () {
                    setState(() {
                      _isDragging = false;
                    });
                    _scheduleAutoHide();
                  },
                  child: AnimatedOpacity(
                    opacity: showControls ? 0.96 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: _thumbHitHeight,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _isDragging
                            ? activeAccent
                            : (isDark ? const Color(0xDD2D333F) : const Color(0xDD1E2430)),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(14),
                          bottomLeft: Radius.circular(14),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(-1, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        '$displayPage',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

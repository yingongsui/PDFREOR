import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

/// An auto-hiding, palm-safe vertical fast scrollbar thumb with a live page
/// indicator bubble. Appears when scrolling or when lightly tapping the screen edge.
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
    double thumbHitHeight = 50.0,
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
  static const double _edgeRevealStripWidth = 18.0;
  static const double _thumbHitWidth = 34.0;
  static const double _thumbHitHeight = 50.0;
  static const double _pillWidth = 22.0;
  static const double _pillHeight = 46.0;
  static const double _bubbleHeight = 34.0;
  static const Duration _autoHideDelay = Duration(milliseconds: 2200);

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

        final double bubbleTop = (metrics.thumbTop + (_thumbHitHeight - _bubbleHeight) / 2.0)
            .clamp(
              widget.topPadding,
              math.max(widget.topPadding, viewportHeight - widget.bottomPadding - _bubbleHeight),
            )
            .toDouble();

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Slim right-bezel tap zone to reveal the scrollbar on a light edge tap
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

            // Non-interactive subtle track line shown only when visible
            Positioned(
              right: 12,
              top: widget.topPadding + (_thumbHitHeight - _pillHeight) / 2.0,
              bottom: widget.bottomPadding + (_thumbHitHeight - _pillHeight) / 2.0,
              width: 3,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: showControls ? 0.32 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),

            // Live page indicator bubble while dragging
            if (_isDragging)
              Positioned(
                right: _thumbHitWidth + 8,
                top: bubbleTop,
                child: IgnorePointer(
                  child: Material(
                    elevation: 6,
                    color: isDark ? const Color(0xF02B313B) : const Color(0xEE1E2430),
                    shadowColor: Colors.black45,
                    borderRadius: BorderRadius.circular(17),
                    child: Container(
                      height: _bubbleHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      alignment: Alignment.center,
                      child: Text(
                        '$displayPage / $totalPages',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Auto-hiding draggable pill thumb
            Positioned(
              right: 2,
              top: metrics.thumbTop,
              width: _thumbHitWidth,
              height: _thumbHitHeight,
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
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedOpacity(
                      opacity: showControls ? 0.96 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        margin: const EdgeInsets.only(right: 2),
                        width: _pillWidth,
                        height: _pillHeight,
                        decoration: BoxDecoration(
                          color: _isDragging
                              ? activeAccent
                              : theme.colorScheme.surface.withValues(alpha: isDark ? 0.92 : 0.95),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: _isDragging
                                ? activeAccent
                                : theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
                            width: 1.0,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 1.5),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.unfold_more_rounded,
                          size: 16,
                          color: _isDragging ? Colors.white : theme.colorScheme.onSurfaceVariant,
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

import 'dart:async';
import 'package:flutter/material.dart';

/// Displays compact floating capsule notifications above all routes and dialogs.
class AppToast {
  AppToast._();

  static OverlayEntry? _activeEntry;
  static int _generation = 0;

  static void dismissCurrent() {
    _generation++;
    final entry = _activeEntry;
    _activeEntry = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }

  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
    double bottomOffset = 28,
  }) {
    if (!context.mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    dismissCurrent();
    final currentGen = _generation;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _FloatingToastOverlay(
        key: ValueKey('app_toast_$currentGen'),
        message: message,
        icon: icon,
        backgroundColor: backgroundColor,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        bottomOffset: bottomOffset,
        onFinished: () {
          if (_generation == currentGen && identical(_activeEntry, entry)) {
            _activeEntry = null;
            if (entry.mounted) {
              entry.remove();
            }
          }
        },
      ),
    );

    _activeEntry = entry;
    overlay.insert(entry);
  }
}

class _FloatingToastOverlay extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Color? backgroundColor;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double bottomOffset;
  final VoidCallback onFinished;

  const _FloatingToastOverlay({
    super.key,
    required this.message,
    required this.icon,
    required this.backgroundColor,
    required this.duration,
    required this.actionLabel,
    required this.onAction,
    required this.bottomOffset,
    required this.onFinished,
  });

  @override
  State<_FloatingToastOverlay> createState() => _FloatingToastOverlayState();
}

class _FloatingToastOverlayState extends State<_FloatingToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  Timer? _hideTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 150),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = curved;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(curved);

    _controller.forward();
    _hideTimer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_isDismissing || !mounted) return;
    _isDismissing = true;
    _hideTimer?.cancel();
    await _controller.reverse();
    if (mounted) {
      widget.onFinished();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Color _resolveBackgroundColor(ThemeData theme) {
    final bg = widget.backgroundColor;
    if (bg == null) return theme.colorScheme.inverseSurface;
    if (bg == Colors.green) return const Color(0xFF1E8E4E);
    if (bg == Colors.red) return const Color(0xFFD93025);
    return bg;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSemantic = widget.backgroundColor != null;
    final bgColor = _resolveBackgroundColor(theme);
    final fgColor = isSemantic ? Colors.white : theme.colorScheme.onInverseSurface;
    final actionColor = isSemantic ? Colors.white : theme.colorScheme.inversePrimary;

    return Positioned(
      left: 24,
      right: 24,
      bottom: widget.bottomOffset,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _opacity,
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding: EdgeInsets.fromLTRB(
                  widget.icon != null ? 14 : 18,
                  widget.actionLabel != null ? 6 : 10,
                  widget.actionLabel != null ? 10 : 18,
                  widget.actionLabel != null ? 6 : 10,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSemantic
                        ? Colors.white.withValues(alpha: 0.16)
                        : theme.colorScheme.outlineVariant.withValues(alpha: 0.28),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, color: fgColor, size: 18),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        widget.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: fgColor,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (widget.actionLabel != null && widget.onAction != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          widget.onAction!.call();
                          _dismiss();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: actionColor,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          widget.actionLabel!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

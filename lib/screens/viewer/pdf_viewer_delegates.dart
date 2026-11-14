import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import '../../widgets/pdf_editor_canvas.dart';

Widget suppressBuiltInContextMenu(
  BuildContext context,
  pdfrx.PdfViewerContextMenuBuilderParams params,
) {
  return const SizedBox.shrink();
}

List<Rect> mergeLineRects(List<Rect> rawRects) {
  if (rawRects.length <= 1) return rawRects;
  final merged = <Rect>[];
  Rect current = rawRects.first;
  for (int i = 1; i < rawRects.length; i++) {
    final next = rawRects[i];
    final minH = math.min(current.height, next.height);
    final maxH = math.max(current.height, next.height);
    final sameLine = minH > 0 &&
        (current.center.dy - next.center.dy).abs() <= minH * 0.45 &&
        next.left >= current.left - maxH * 0.5 &&
        (next.left - current.right) <= maxH * 0.85;
    if (sameLine) {
      current = current.expandToInclude(next);
    } else {
      merged.add(current);
      current = next;
    }
  }
  merged.add(current);
  return merged;
}

class PdfTextSelectionMenu extends StatelessWidget {
  final Rect localRect;
  final Size canvasSize;
  final Color highlightColor;
  final Color underlineColor;
  final VoidCallback onCopy;
  final VoidCallback onHighlight;
  final VoidCallback onUnderline;
  final VoidCallback onStrikethrough;

  const PdfTextSelectionMenu({
    super.key,
    required this.localRect,
    required this.canvasSize,
    required this.highlightColor,
    required this.underlineColor,
    required this.onCopy,
    required this.onHighlight,
    required this.onUnderline,
    required this.onStrikethrough,
  });

  @override
  Widget build(BuildContext context) {
    final fallbackSize = MediaQuery.sizeOf(context);
    final viewportWidth = canvasSize.width > 0 ? canvasSize.width : fallbackSize.width;
    final viewportHeight = canvasSize.height > 0 ? canvasSize.height : fallbackSize.height;
    const menuHeight = 44.0;
    const idealMenuWidth = 360.0;
    final maxAllowedWidth = math.max(120.0, math.min(idealMenuWidth, viewportWidth - 24.0));

    final selCenter = localRect.center.dx;
    double left = selCenter - (maxAllowedWidth / 2);
    if (left + maxAllowedWidth > viewportWidth - 12.0) {
      left = viewportWidth - maxAllowedWidth - 12.0;
    }
    if (left < 12.0) {
      left = 12.0;
    }

    double top = localRect.top - menuHeight - 10.0;
    if (top < 56.0) {
      top = localRect.bottom + 10.0;
    }
    if (top > viewportHeight - menuHeight - 16.0) {
      top = viewportHeight - menuHeight - 16.0;
    }
    if (top < 8.0) {
      top = 8.0;
    }

    final theme = Theme.of(context);

    return Positioned(
      left: left,
      top: top,
      child: TapRegion(
        groupId: kEditableElementRegionGroup,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(22),
          color: theme.colorScheme.surface,
          shadowColor: Colors.black45,
          child: Container(
            height: menuHeight,
            constraints: BoxConstraints(maxWidth: maxAllowedWidth),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 4),
                  _buildTextMenuItem(
                    theme: theme,
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onTap: onCopy,
                  ),
                  Container(
                    height: 20,
                    width: 1,
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                  _buildTextMenuItem(
                    theme: theme,
                    icon: Icons.border_color_rounded,
                    iconColor: highlightColor,
                    label: 'Highlight',
                    onTap: onHighlight,
                  ),
                  _buildTextMenuItem(
                    theme: theme,
                    icon: Icons.format_underlined_rounded,
                    iconColor: underlineColor,
                    label: 'Underline',
                    onTap: onUnderline,
                  ),
                  _buildTextMenuItem(
                    theme: theme,
                    icon: Icons.format_strikethrough_rounded,
                    iconColor: const Color(0xFFF44336),
                    label: 'Strike',
                    onTap: onStrikethrough,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextMenuItem({
    required ThemeData theme,
    required IconData icon,
    required String label,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor ?? theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DeferredInitSmartSizeDelegateProvider extends pdfrx.PdfViewerSizeDelegateProvider {
  const DeferredInitSmartSizeDelegateProvider({required this.inner});

  final pdfrx.PdfViewerSizeDelegateProviderSmart inner;

  @override
  pdfrx.PdfViewerSizeDelegate create() => _DeferredInitSmartSizeDelegate(inner.create());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeferredInitSmartSizeDelegateProvider && other.inner == inner);

  @override
  int get hashCode => inner.hashCode;
}

class _DeferredInitSmartSizeDelegate implements pdfrx.PdfViewerSizeDelegate {
  _DeferredInitSmartSizeDelegate(this._inner);

  final pdfrx.PdfViewerSizeDelegate _inner;

  @override
  double get onePassRenderingScaleThreshold => _inner.onePassRenderingScaleThreshold;

  @override
  void init(pdfrx.PdfViewerController controller) => _inner.init(controller);

  @override
  void dispose() => _inner.dispose();

  @override
  pdfrx.PdfViewerLayoutMetrics calculateMetrics({
    required Size viewSize,
    required pdfrx.PdfPageLayout? layout,
    required int? pageNumber,
    required double pageMargin,
    required EdgeInsets? boundaryMargin,
  }) => _inner.calculateMetrics(
    viewSize: viewSize,
    layout: layout,
    pageNumber: pageNumber,
    pageMargin: pageMargin,
    boundaryMargin: boundaryMargin,
  );

  @override
  void onLayoutInitialized({
    required pdfrx.PdfViewerLayoutSnapshot state,
    required int initialPageNumber,
    required double coverScale,
    required double? alternativeFitScale,
    required pdfrx.PdfPageLayout layout,
    required pdfrx.PdfDocument document,
  }) {
    // Initial zoom and viewport offset are applied synchronously in _onViewerReady.
  }

  @override
  void onLayoutUpdate({
    required pdfrx.PdfViewerLayoutSnapshot oldState,
    required pdfrx.PdfViewerLayoutSnapshot newState,
    required double currentZoom,
    required Rect oldVisibleRect,
    required int? anchorPageNumber,
    required bool isLayoutChanged,
    required bool isViewSizeChanged,
  }) => _inner.onLayoutUpdate(
    oldState: oldState,
    newState: newState,
    currentZoom: currentZoom,
    oldVisibleRect: oldVisibleRect,
    anchorPageNumber: anchorPageNumber,
    isLayoutChanged: isLayoutChanged,
    isViewSizeChanged: isViewSizeChanged,
  );
}

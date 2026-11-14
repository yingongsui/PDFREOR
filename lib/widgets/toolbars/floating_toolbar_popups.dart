import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/editor_models.dart';
import 'editor_palette.dart';

/// Anchored popup dialogs (color palette, stroke width, font size, shape picker)
/// launched from [PdfFloatingToolbar].
class FloatingToolbarPopups {
  FloatingToolbarPopups._();

  static const List<Color> defaultPalette = kEditorToolbarPalette;

  static void showAnchoredPopup(
    BuildContext hostContext,
    BuildContext buttonContext,
    Widget Function(BuildContext dialogContext) builder,
  ) {
    final renderBox = buttonContext.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? const Offset(100, 100);
    final size = renderBox?.size ?? const Size(48, 48);
    final screenSize = MediaQuery.of(hostContext).size;

    final isLeftHalf = offset.dx < screenSize.width / 2;
    final left = isLeftHalf ? offset.dx + size.width + 10 : null;
    final right = !isLeftHalf ? (screenSize.width - offset.dx) + 10 : null;
    final top = (offset.dy - 60).clamp(40.0, math.max(40.0, screenSize.height - 380.0)).toDouble();

    showGeneralDialog(
      context: hostContext,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.12),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Stack(
          children: [
            Positioned(
              left: left,
              right: right,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: builder(dialogContext),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            alignment: isLeftHalf ? Alignment.centerLeft : Alignment.centerRight,
            child: child,
          ),
        );
      },
    );
  }

  static Widget _buildPopupHeader(ThemeData theme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  static void showColorPicker({
    required BuildContext hostContext,
    required BuildContext buttonContext,
    required Color activeColor,
    required ValueChanged<Color> onColorSelected,
    List<Color> palette = defaultPalette,
  }) {
    showAnchoredPopup(hostContext, buttonContext, (dialogContext) {
      final theme = Theme.of(hostContext);
      return Card(
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: theme.colorScheme.surface,
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPopupHeader(theme, Icons.palette_outlined, 'Color Palette'),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: palette.map((color) {
                  final isSelected = activeColor.toARGB32() == color.toARGB32();
                  return EditorColorDot(
                    color: color,
                    isSelected: isSelected,
                    size: 32,
                    selectedBorderWidth: 3,
                    shadowBlurRadius: 6,
                    shadowSpreadRadius: 2,
                    checkIconSize: 18,
                    onTap: () {
                      onColorSelected(color);
                      Navigator.pop(dialogContext);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    });
  }

  static void showStrokeWidthPicker({
    required BuildContext hostContext,
    required BuildContext buttonContext,
    required double activeStrokeWidth,
    required ValueChanged<double> onStrokeWidthSelected,
  }) {
    showAnchoredPopup(hostContext, buttonContext, (dialogContext) {
      final theme = Theme.of(hostContext);
      const widths = [1.0, 1.5, 2.0, 3.0, 5.0, 8.0, 12.0];
      return Card(
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: theme.colorScheme.surface,
        child: Container(
          width: 210,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPopupHeader(theme, Icons.line_weight_rounded, 'Stroke Width'),
              const SizedBox(height: 12),
              Column(
                children: widths.map((width) {
                  final isSelected = (activeStrokeWidth - width).abs() < 0.1;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      onStrokeWidthSelected(width);
                      Navigator.pop(dialogContext);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 52,
                            child: Text(
                              '${width.toStringAsFixed(1)} pt',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? theme.colorScheme.primary : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              height: width,
                              decoration: BoxDecoration(
                                color: isSelected ? theme.colorScheme.primary : Colors.grey.shade600,
                                borderRadius: BorderRadius.circular(width / 2),
                              ),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check_rounded, size: 16, color: theme.colorScheme.primary),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    });
  }

  static void showFontSizePicker({
    required BuildContext hostContext,
    required BuildContext buttonContext,
    required double activeFontSize,
    ValueChanged<double>? onFontSizeSelected,
  }) {
    showAnchoredPopup(hostContext, buttonContext, (dialogContext) {
      final theme = Theme.of(hostContext);
      const fontSizes = [10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0];
      return Card(
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: theme.colorScheme.surface,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPopupHeader(theme, Icons.format_size_rounded, 'Font Size'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: fontSizes.map((size) {
                  final isSelected = (activeFontSize - size).abs() < 0.1;
                  return ChoiceChip(
                    label: Text('${size.toInt()} pt'),
                    selected: isSelected,
                    visualDensity: VisualDensity.compact,
                    onSelected: (selected) {
                      if (selected) {
                        onFontSizeSelected?.call(size);
                        Navigator.pop(dialogContext);
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    });
  }

  static void showShapePicker({
    required BuildContext hostContext,
    required BuildContext buttonContext,
    required EditorTool activeTool,
    required ShapeType activeShape,
    required ValueChanged<EditorTool> onToolSelected,
    required ValueChanged<ShapeType> onShapeSelected,
  }) {
    showAnchoredPopup(hostContext, buttonContext, (dialogContext) {
      final theme = Theme.of(hostContext);
      return Card(
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: theme.colorScheme.surface,
        child: Container(
          width: 216,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _buildPopupHeader(theme, Icons.category_outlined, 'Select Shape'),
              ),
              const Divider(height: 1),
              _buildShapeOption(
                dialogContext,
                type: ShapeType.rectangle,
                icon: Icons.rectangle_outlined,
                title: 'Rectangle',
                activeTool: activeTool,
                activeShape: activeShape,
                onToolSelected: onToolSelected,
                onShapeSelected: onShapeSelected,
              ),
              _buildShapeOption(
                dialogContext,
                type: ShapeType.roundedRectangle,
                icon: Icons.rounded_corner_rounded,
                title: 'Rounded Rectangle',
                activeTool: activeTool,
                activeShape: activeShape,
                onToolSelected: onToolSelected,
                onShapeSelected: onShapeSelected,
              ),
              _buildShapeOption(
                dialogContext,
                type: ShapeType.circle,
                icon: Icons.circle_outlined,
                title: 'Circle / Ellipse',
                activeTool: activeTool,
                activeShape: activeShape,
                onToolSelected: onToolSelected,
                onShapeSelected: onShapeSelected,
              ),
              _buildShapeOption(
                dialogContext,
                type: ShapeType.line,
                icon: Icons.horizontal_rule_rounded,
                title: 'Straight Line',
                activeTool: activeTool,
                activeShape: activeShape,
                onToolSelected: onToolSelected,
                onShapeSelected: onShapeSelected,
              ),
              _buildShapeOption(
                dialogContext,
                type: ShapeType.arrow,
                icon: Icons.arrow_forward_rounded,
                title: 'Arrow',
                activeTool: activeTool,
                activeShape: activeShape,
                onToolSelected: onToolSelected,
                onShapeSelected: onShapeSelected,
              ),
            ],
          ),
        ),
      );
    });
  }

  static Widget _buildShapeOption(
    BuildContext dialogContext, {
    required ShapeType type,
    required IconData icon,
    required String title,
    required EditorTool activeTool,
    required ShapeType activeShape,
    required ValueChanged<EditorTool> onToolSelected,
    required ValueChanged<ShapeType> onShapeSelected,
  }) {
    final isSelected = activeTool == EditorTool.shape && activeShape == type;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      trailing: isSelected ? const Icon(Icons.check, size: 18, color: Colors.blue) : null,
      onTap: () {
        onToolSelected(EditorTool.shape);
        onShapeSelected(type);
        Navigator.pop(dialogContext);
      },
    );
  }
}

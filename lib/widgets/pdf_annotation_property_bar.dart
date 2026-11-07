import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/editor_models.dart';
import 'pdf_canvas_items.dart';

class PdfAnnotationPropertyBar extends StatelessWidget {
  final DrawnTextAnnotation? activeTextAnnotation;
  final DrawnShape? activeShape;
  final DrawingStroke? activeStroke;
  final DrawnTextBox? activeTextBox;

  final ValueChanged<Color> onTextAnnotationColorChanged;
  final VoidCallback onDeleteTextAnnotation;
  final VoidCallback onDoneTextAnnotation;

  final ValueChanged<double> onShapeStrokeWidthChanged;
  final ValueChanged<Color> onShapeColorChanged;
  final VoidCallback onDeleteShape;
  final VoidCallback onDoneShape;

  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<Color> onStrokeColorChanged;
  final VoidCallback onDeleteStroke;
  final VoidCallback onDoneStroke;

  final ValueChanged<double> onTextBoxFontSizeChanged;
  final ValueChanged<Color> onTextBoxColorChanged;
  final VoidCallback onDeleteTextBox;
  final VoidCallback onDoneTextBox;

  const PdfAnnotationPropertyBar({
    super.key,
    this.activeTextAnnotation,
    this.activeShape,
    this.activeStroke,
    this.activeTextBox,
    required this.onTextAnnotationColorChanged,
    required this.onDeleteTextAnnotation,
    required this.onDoneTextAnnotation,
    required this.onShapeStrokeWidthChanged,
    required this.onShapeColorChanged,
    required this.onDeleteShape,
    required this.onDoneShape,
    required this.onStrokeWidthChanged,
    required this.onStrokeColorChanged,
    required this.onDeleteStroke,
    required this.onDoneStroke,
    required this.onTextBoxFontSizeChanged,
    required this.onTextBoxColorChanged,
    required this.onDeleteTextBox,
    required this.onDoneTextBox,
  });

  static const List<Color> _annotationPalette = [
    Color(0xFFFFEB3B), // Yellow (Highlighter)
    Color(0xFFFF9800), // Orange
    Color(0xFFF44336), // Red
    Color(0xFFE91E63), // Pink
    Color(0xFF9C27B0), // Purple
    Color(0xFF2196F3), // Blue
    Color(0xFF009688), // Teal
    Color(0xFF4CAF50), // Green
  ];

  static const List<Color> _inkPalette = [
    Color(0xFF212121), // Black
    Color(0xFFD32F2F), // Red
    Color(0xFF1976D2), // Blue
    Color(0xFF388E3C), // Green
    Color(0xFFF57C00), // Orange
    Color(0xFF7B1FA2), // Purple
    Color(0xFF0097A7), // Cyan
    Color(0xFF757575), // Gray
  ];

  @override
  Widget build(BuildContext context) {
    if (activeTextAnnotation == null &&
        activeShape == null &&
        activeStroke == null &&
        activeTextBox == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    Widget content;
    if (activeTextAnnotation != null) {
      content = _buildTextAnnotationBarContent(activeTextAnnotation!, theme);
    } else if (activeShape != null) {
      content = _buildShapeBarContent(activeShape!, theme);
    } else if (activeStroke != null) {
      content = _buildStrokeBarContent(activeStroke!, theme);
    } else {
      content = _buildTextBoxBarContent(activeTextBox!, theme);
    }

    return Positioned(
      left: 12,
      right: 12,
      top: 10,
      child: Center(
        child: TapRegion(
          groupId: kEditableElementRegionGroup,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.surface,
            shadowColor: Colors.black45,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextAnnotationBarContent(DrawnTextAnnotation annotation, ThemeData theme) {
    IconData icon;
    String label;
    switch (annotation.type) {
      case TextAnnotationType.highlight:
        icon = Icons.border_color_rounded;
        label = 'Highlight';
        break;
      case TextAnnotationType.underline:
        icon = Icons.format_underlined_rounded;
        label = 'Underline';
        break;
      case TextAnnotationType.strikethrough:
        icon = Icons.format_strikethrough_rounded;
        label = 'Strikethrough';
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: _annotationPalette.map((color) {
            final isSelected =
                (annotation.color.toARGB32() & 0x00FFFFFF) == (color.toARGB32() & 0x00FFFFFF);
            return _buildColorDot(
              color: color,
              isSelected: isSelected,
              theme: theme,
              onTap: () => onTextAnnotationColorChanged(color),
            );
          }).toList(),
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),
        _buildActionButton(
          icon: Icons.delete_outline_rounded,
          color: Colors.red,
          backgroundColor: const Color(0xFFFFEBEE),
          tooltip: 'Delete',
          onTap: onDeleteTextAnnotation,
        ),
        const SizedBox(width: 6),
        _buildActionButton(
          icon: Icons.check_rounded,
          color: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          tooltip: 'Done',
          onTap: onDoneTextAnnotation,
        ),
      ],
    );
  }

  Widget _buildShapeBarContent(DrawnShape shape, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(shape.type.icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          shape.type.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),
        _buildStepperButton(
          icon: Icons.remove,
          theme: theme,
          onTap: () {
            if (shape.strokeWidth > 1.0) {
              onShapeStrokeWidthChanged(math.max(1.0, shape.strokeWidth - 1.0));
            }
          },
        ),
        SizedBox(
          width: 48,
          child: Text(
            '${shape.strokeWidth.toStringAsFixed(1)} pt',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        _buildStepperButton(
          icon: Icons.add,
          theme: theme,
          onTap: () {
            if (shape.strokeWidth < 20.0) {
              onShapeStrokeWidthChanged(math.min(20.0, shape.strokeWidth + 1.0));
            }
          },
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: _inkPalette.map((color) {
            final isSelected =
                (shape.color.toARGB32() & 0x00FFFFFF) == (color.toARGB32() & 0x00FFFFFF);
            return _buildColorDot(
              color: color,
              isSelected: isSelected,
              theme: theme,
              onTap: () => onShapeColorChanged(color),
            );
          }).toList(),
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),
        _buildActionButton(
          icon: Icons.delete_outline_rounded,
          color: Colors.red,
          backgroundColor: const Color(0xFFFFEBEE),
          tooltip: 'Delete Shape',
          onTap: onDeleteShape,
        ),
        const SizedBox(width: 6),
        _buildActionButton(
          icon: Icons.check_rounded,
          color: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          tooltip: 'Done',
          onTap: onDoneShape,
        ),
      ],
    );
  }

  Widget _buildStrokeBarContent(DrawingStroke stroke, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.edit_rounded, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          'Stroke',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),
        _buildStepperButton(
          icon: Icons.remove,
          theme: theme,
          onTap: () {
            if (stroke.strokeWidth > 1.0) {
              onStrokeWidthChanged(math.max(1.0, stroke.strokeWidth - 1.0));
            }
          },
        ),
        SizedBox(
          width: 48,
          child: Text(
            '${stroke.strokeWidth.toStringAsFixed(1)} pt',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        _buildStepperButton(
          icon: Icons.add,
          theme: theme,
          onTap: () {
            if (stroke.strokeWidth < 30.0) {
              onStrokeWidthChanged(math.min(30.0, stroke.strokeWidth + 1.0));
            }
          },
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: _inkPalette.map((color) {
            final isSelected =
                (stroke.color.toARGB32() & 0x00FFFFFF) == (color.toARGB32() & 0x00FFFFFF);
            return _buildColorDot(
              color: color,
              isSelected: isSelected,
              theme: theme,
              onTap: () => onStrokeColorChanged(color),
            );
          }).toList(),
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),
        _buildActionButton(
          icon: Icons.delete_outline_rounded,
          color: Colors.red,
          backgroundColor: const Color(0xFFFFEBEE),
          tooltip: 'Delete Stroke',
          onTap: onDeleteStroke,
        ),
        const SizedBox(width: 6),
        _buildActionButton(
          icon: Icons.check_rounded,
          color: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          tooltip: 'Done',
          onTap: onDoneStroke,
        ),
      ],
    );
  }

  Widget _buildTextBoxBarContent(DrawnTextBox tb, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.text_fields_rounded, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          'Text',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),
        _buildStepperButton(
          icon: Icons.remove,
          theme: theme,
          onTap: () {
            if (tb.fontSize > 8) {
              onTextBoxFontSizeChanged(tb.fontSize - 2);
            }
          },
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${tb.fontSize.toInt()} pt',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        _buildStepperButton(
          icon: Icons.add,
          theme: theme,
          onTap: () {
            if (tb.fontSize < 72) {
              onTextBoxFontSizeChanged(tb.fontSize + 2);
            }
          },
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: _inkPalette.map((color) {
            final isSelected =
                (tb.color.toARGB32() & 0x00FFFFFF) == (color.toARGB32() & 0x00FFFFFF);
            return _buildColorDot(
              color: color,
              isSelected: isSelected,
              theme: theme,
              onTap: () => onTextBoxColorChanged(color),
            );
          }).toList(),
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),
        _buildActionButton(
          icon: Icons.delete_outline_rounded,
          color: Colors.red,
          backgroundColor: const Color(0xFFFFEBEE),
          tooltip: 'Delete Text',
          onTap: onDeleteTextBox,
        ),
        const SizedBox(width: 6),
        _buildActionButton(
          icon: Icons.check_rounded,
          color: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          tooltip: 'Done',
          onTap: onDoneTextBox,
        ),
      ],
    );
  }

  Widget _buildBarDivider(ThemeData theme) {
    return Container(
      height: 20,
      width: 1,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required ThemeData theme,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
        child: Icon(icon, size: 16, color: theme.colorScheme.onSurface),
      ),
    );
  }

  Widget _buildColorDot({
    required Color color,
    required bool isSelected,
    required ThemeData theme,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? theme.colorScheme.primary : Colors.black26,
              width: isSelected ? 2.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  size: 14,
                  color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}


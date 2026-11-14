import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/editor_models.dart';
import 'pdf_canvas_items.dart';
import 'toolbars/editor_palette.dart';

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

  @override
  Widget build(BuildContext context) {
    if (activeTextAnnotation == null &&
        activeShape == null &&
        activeStroke == null &&
        activeTextBox == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final Widget content;
    if (activeTextAnnotation != null) {
      content = _buildTextAnnotationBarContent(activeTextAnnotation!, theme);
    } else if (activeShape != null) {
      final shape = activeShape!;
      content = _buildPropertyBarRow(
        theme: theme,
        icon: shape.type.icon,
        label: shape.type.label,
        stepperControl: _buildNumericStepper(
          theme: theme,
          label: '${shape.strokeWidth.toStringAsFixed(1)} pt',
          labelWidth: 48,
          onDecrement: shape.strokeWidth > 1.0
              ? () => onShapeStrokeWidthChanged(math.max(1.0, shape.strokeWidth - 1.0))
              : null,
          onIncrement: shape.strokeWidth < 20.0
              ? () => onShapeStrokeWidthChanged(math.min(20.0, shape.strokeWidth + 1.0))
              : null,
        ),
        palette: kEditorInkPalette,
        selectedColor: shape.color,
        onColorChanged: onShapeColorChanged,
        deleteTooltip: 'Delete Shape',
        onDelete: onDeleteShape,
        onDone: onDoneShape,
      );
    } else if (activeStroke != null) {
      final stroke = activeStroke!;
      content = _buildPropertyBarRow(
        theme: theme,
        icon: Icons.edit_rounded,
        label: 'Stroke',
        stepperControl: _buildNumericStepper(
          theme: theme,
          label: '${stroke.strokeWidth.toStringAsFixed(1)} pt',
          labelWidth: 48,
          onDecrement: stroke.strokeWidth > 1.0
              ? () => onStrokeWidthChanged(math.max(1.0, stroke.strokeWidth - 1.0))
              : null,
          onIncrement: stroke.strokeWidth < 30.0
              ? () => onStrokeWidthChanged(math.min(30.0, stroke.strokeWidth + 1.0))
              : null,
        ),
        palette: kEditorInkPalette,
        selectedColor: stroke.color,
        onColorChanged: onStrokeColorChanged,
        deleteTooltip: 'Delete Stroke',
        onDelete: onDeleteStroke,
        onDone: onDoneStroke,
      );
    } else {
      final tb = activeTextBox!;
      content = _buildPropertyBarRow(
        theme: theme,
        icon: Icons.text_fields_rounded,
        label: 'Text',
        stepperControl: _buildNumericStepper(
          theme: theme,
          label: '${tb.fontSize.toInt()} pt',
          labelWidth: 40,
          onDecrement: tb.fontSize > 8 ? () => onTextBoxFontSizeChanged(tb.fontSize - 2) : null,
          onIncrement: tb.fontSize < 72 ? () => onTextBoxFontSizeChanged(tb.fontSize + 2) : null,
        ),
        palette: kEditorInkPalette,
        selectedColor: tb.color,
        onColorChanged: onTextBoxColorChanged,
        deleteTooltip: 'Delete Text',
        onDelete: onDeleteTextBox,
        onDone: onDoneTextBox,
      );
    }

    return Positioned(
      left: 12,
      right: 12,
      top: math.max(10.0, MediaQuery.paddingOf(context).top + 6.0),
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
    final (IconData icon, String label) = switch (annotation.type) {
      TextAnnotationType.highlight => (Icons.border_color_rounded, 'Highlight'),
      TextAnnotationType.underline => (Icons.format_underlined_rounded, 'Underline'),
      TextAnnotationType.strikethrough => (Icons.format_strikethrough_rounded, 'Strikethrough'),
    };
    return _buildPropertyBarRow(
      theme: theme,
      icon: icon,
      label: label,
      palette: kEditorAnnotationPalette,
      selectedColor: annotation.color,
      onColorChanged: onTextAnnotationColorChanged,
      deleteTooltip: 'Delete',
      onDelete: onDeleteTextAnnotation,
      onDone: onDoneTextAnnotation,
    );
  }

  Widget _buildPropertyBarRow({
    required ThemeData theme,
    required IconData icon,
    required String label,
    Widget? stepperControl,
    required List<Color> palette,
    required Color selectedColor,
    required ValueChanged<Color> onColorChanged,
    required String deleteTooltip,
    required VoidCallback onDelete,
    required VoidCallback onDone,
  }) {
    final selectedRgb = selectedColor.toARGB32() & 0x00FFFFFF;
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
        if (stepperControl != null) ...[
          stepperControl,
          const SizedBox(width: 8),
          _buildBarDivider(theme),
          const SizedBox(width: 8),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: palette.map((color) {
            final isSelected = selectedRgb == (color.toARGB32() & 0x00FFFFFF);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: EditorColorDot(
                color: color,
                isSelected: isSelected,
                size: 24,
                selectedBorderColor: theme.colorScheme.primary,
                onTap: () => onColorChanged(color),
              ),
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
          tooltip: deleteTooltip,
          onTap: onDelete,
        ),
        const SizedBox(width: 6),
        _buildActionButton(
          icon: Icons.check_rounded,
          color: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          tooltip: 'Done',
          onTap: onDone,
        ),
      ],
    );
  }

  Widget _buildNumericStepper({
    required ThemeData theme,
    required String label,
    required double labelWidth,
    VoidCallback? onDecrement,
    VoidCallback? onIncrement,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStepperButton(
          icon: Icons.remove,
          theme: theme,
          onTap: onDecrement ?? () {},
        ),
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
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
          onTap: onIncrement ?? () {},
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

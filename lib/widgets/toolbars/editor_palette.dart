import 'package:flutter/material.dart';

/// Highlight / text annotation palette shared across editor toolbars.
const List<Color> kEditorAnnotationPalette = [
  Color(0xFFFFEB3B), // Yellow (Highlighter)
  Color(0xFFFF9800), // Orange
  Color(0xFFF44336), // Red
  Color(0xFFE91E63), // Pink
  Color(0xFF9C27B0), // Purple
  Color(0xFF2196F3), // Blue
  Color(0xFF009688), // Teal
  Color(0xFF4CAF50), // Green
];

/// Full toolbar palette adding Black to [kEditorAnnotationPalette].
const List<Color> kEditorToolbarPalette = [
  ...kEditorAnnotationPalette,
  Color(0xFF212121), // Black
];

/// Ink / shape / text box palette used in the annotation property bar.
const List<Color> kEditorInkPalette = [
  Color(0xFF212121), // Black
  Color(0xFFD32F2F), // Red
  Color(0xFF1976D2), // Blue
  Color(0xFF388E3C), // Green
  Color(0xFFF57C00), // Orange
  Color(0xFF7B1FA2), // Purple
  Color(0xFF0097A7), // Cyan
  Color(0xFF757575), // Gray
];

/// Reusable circular swatch button with selection ring, drop shadow, and
/// contrast-aware checkmark shared by toolbars and property bars.
class EditorColorDot extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final double size;
  final Color selectedBorderColor;
  final double selectedBorderWidth;
  final double shadowBlurRadius;
  final double shadowSpreadRadius;
  final double checkIconSize;

  const EditorColorDot({
    super.key,
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.size = 24,
    this.selectedBorderColor = Colors.white,
    this.selectedBorderWidth = 2.5,
    this.shadowBlurRadius = 4,
    this.shadowSpreadRadius = 1,
    this.checkIconSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? selectedBorderColor : Colors.black26,
            width: isSelected ? selectedBorderWidth : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: shadowBlurRadius,
                    spreadRadius: shadowSpreadRadius,
                  ),
                ]
              : null,
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                size: checkIconSize,
                color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
              )
            : null,
      ),
    );
  }
}

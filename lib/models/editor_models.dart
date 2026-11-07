import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

enum EditorTool {
  select, // Navigation & text selection
  pen, // Freehand stylus / pen drawing
  eraser, // Stroke eraser (erases whole continuous stroke)
  shape, // Geometric shapes (rectangle, circle, line, arrow)
  textBox, // Add text box
  latexBox, // Add LaTeX math formula box
}

enum ShapeType {
  rectangle,
  circle,
  line,
  arrow;

  IconData get icon {
    switch (this) {
      case ShapeType.rectangle:
        return Icons.rectangle_outlined;
      case ShapeType.circle:
        return Icons.circle_outlined;
      case ShapeType.line:
        return Icons.horizontal_rule_rounded;
      case ShapeType.arrow:
        return Icons.arrow_forward_rounded;
    }
  }

  String get label {
    switch (this) {
      case ShapeType.rectangle:
        return 'Rectangle';
      case ShapeType.circle:
        return 'Circle';
      case ShapeType.line:
        return 'Line';
      case ShapeType.arrow:
        return 'Arrow';
    }
  }
}

void paintShapeOnCanvas(
  Canvas canvas,
  ShapeType type,
  Offset start,
  Offset end,
  Paint paint,
) {
  final rect = Rect.fromPoints(start, end);
  switch (type) {
    case ShapeType.rectangle:
      canvas.drawRect(rect, paint);
      break;
    case ShapeType.circle:
      canvas.drawOval(rect, paint);
      break;
    case ShapeType.line:
      canvas.drawLine(start, end, paint);
      break;
    case ShapeType.arrow:
      canvas.drawLine(start, end, paint);
      final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
      final arrowLength = math.max(paint.strokeWidth * 4.0, 12.0);
      const arrowAngle = math.pi / 6;
      final p1 = Offset(
        end.dx - arrowLength * math.cos(angle - arrowAngle),
        end.dy - arrowLength * math.sin(angle - arrowAngle),
      );
      final p2 = Offset(
        end.dx - arrowLength * math.cos(angle + arrowAngle),
        end.dy - arrowLength * math.sin(angle + arrowAngle),
      );
      canvas.drawLine(end, p1, paint);
      canvas.drawLine(end, p2, paint);
      break;
  }
}

enum TextAnnotationType {
  highlight,
  underline,
  strikethrough,
}

class DrawnTextAnnotation {
  final String id;
  final TextAnnotationType type;
  final List<Rect> rects;
  Color color;
  final int pageNumber;
  Rect? _cachedBounds;

  DrawnTextAnnotation({
    String? id,
    required this.type,
    required this.rects,
    required this.color,
    required this.pageNumber,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  void invalidateBounds() {
    _cachedBounds = null;
  }

  Rect getBounds() {
    final cached = _cachedBounds;
    if (cached != null) return cached;
    if (rects.isEmpty) {
      _cachedBounds = Rect.zero;
      return Rect.zero;
    }
    Rect b = rects.first;
    for (int i = 1; i < rects.length; i++) {
      b = b.expandToInclude(rects[i]);
    }
    _cachedBounds = b;
    return b;
  }
}

class StrokePoint {
  final Offset offset;
  final double pressure;

  const StrokePoint({
    required this.offset,
    this.pressure = 1.0,
  });
}

class DrawingStroke {
  final String id;
  final List<StrokePoint> points;
  Color color;
  double strokeWidth;
  final int pageNumber;
  Rect? _cachedBounds;

  DrawingStroke({
    String? id,
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.pageNumber,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  void invalidateBounds() {
    _cachedBounds = null;
  }

  Rect getBounds() {
    final cached = _cachedBounds;
    if (cached != null) return cached;
    if (points.isEmpty) {
      _cachedBounds = Rect.zero;
      return Rect.zero;
    }
    double minX = points.first.offset.dx;
    double maxX = minX;
    double minY = points.first.offset.dy;
    double maxY = minY;
    for (int i = 1; i < points.length; i++) {
      final p = points[i].offset;
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final b = Rect.fromLTRB(minX, minY, maxX, maxY);
    _cachedBounds = b;
    return b;
  }
}

class DrawnShape {
  final String id;
  final ShapeType type;
  Offset start;
  Offset end;
  Color color;
  double strokeWidth;
  final int pageNumber;

  DrawnShape({
    String? id,
    required this.type,
    required this.start,
    required this.end,
    required this.color,
    required this.strokeWidth,
    required this.pageNumber,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();
}

class DrawnTextBox {
  final String id;
  String text;
  Offset position;
  double fontSize;
  Color color;
  final int pageNumber;
  double? width;
  final bool isLatex;

  DrawnTextBox({
    required this.id,
    required this.text,
    required this.position,
    this.fontSize = 16.0,
    required this.color,
    required this.pageNumber,
    this.width,
    this.isLatex = false,
  });
}

class DrawnImage {
  final String id;
  final Uint8List imageBytes;
  Offset position;
  double width;
  double height;
  final int pageNumber;

  DrawnImage({
    required this.id,
    required this.imageBytes,
    required this.position,
    required this.width,
    required this.height,
    required this.pageNumber,
  });
}


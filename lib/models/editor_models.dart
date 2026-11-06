import 'dart:typed_data';
import 'dart:ui';

enum EditorTool {
  select, // Navigation & text selection
  highlight, // Text highlight
  underline, // Text underline
  pen, // Freehand stylus / pen drawing
  eraser, // Stroke eraser (erases whole continuous stroke)
  shape, // Geometric shapes (rectangle, circle, line, arrow)
  textBox, // Add text box
}

enum ShapeType {
  rectangle,
  circle,
  line,
  arrow,
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

  DrawnTextBox({
    required this.id,
    required this.text,
    required this.position,
    this.fontSize = 16.0,
    required this.color,
    required this.pageNumber,
    this.width,
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


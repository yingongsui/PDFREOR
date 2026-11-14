import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

bool isStylusPointer(PointerEvent event) {
  return event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;
}

bool isEraserButtonPressed(PointerEvent event) {
  return (event.buttons &
          (kPrimaryStylusButton | kSecondaryStylusButton | kSecondaryMouseButton)) !=
      0;
}

const List<ShapeType> kOrderedShapeTypes = <ShapeType>[
  ShapeType.rectangle,
  ShapeType.roundedRectangle,
  ShapeType.circle,
  ShapeType.line,
  ShapeType.arrow,
];

int _annotationIdSeq = 0;

/// Generates a collision-free unique annotation identifier even when multiple
/// annotations are created within the same microsecond.
String nextAnnotationId([String prefix = 'ann']) {
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_annotationIdSeq++}';
}

enum EditorTool {
  select, // Navigation & text selection
  pen, // Freehand stylus / pen drawing
  eraser, // Stroke eraser (erases whole continuous stroke)
  shape, // Geometric shapes (rectangle, roundedRectangle, circle, line, arrow)
  textBox, // Add text box
  latexBox, // Add LaTeX math formula box
}

enum ShapeType {
  rectangle,
  circle,
  line,
  arrow,
  roundedRectangle;

  IconData get icon {
    switch (this) {
      case ShapeType.rectangle:
        return Icons.rectangle_outlined;
      case ShapeType.roundedRectangle:
        return Icons.rounded_corner_rounded;
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
      case ShapeType.roundedRectangle:
        return 'Rounded Rect';
      case ShapeType.circle:
        return 'Circle';
      case ShapeType.line:
        return 'Line';
      case ShapeType.arrow:
        return 'Arrow';
    }
  }
}

double roundedRectCornerRadius(Rect rect) {
  final minSide = math.min(rect.width.abs(), rect.height.abs());
  return math.min(20.0, minSide * 0.2);
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
    case ShapeType.roundedRectangle:
      final radius = roundedRectCornerRadius(rect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );
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
  }) : id = id ?? nextAnnotationId('ta');

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

class StrokePathBatch {
  final double strokeWidth;
  final Path path;

  const StrokePathBatch(this.strokeWidth, this.path);
}

class DrawingStroke {
  final String id;
  final List<StrokePoint> points;
  Color color;
  double strokeWidth;
  final int pageNumber;
  Rect? _cachedBounds;
  List<StrokePathBatch>? _cachedPathBatches;
  double? _cachedForWidth;

  DrawingStroke({
    String? id,
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.pageNumber,
  }) : id = id ?? nextAnnotationId('st');

  void invalidateBounds() {
    _cachedBounds = null;
    _cachedPathBatches = null;
    _cachedForWidth = null;
  }

  /// Returns cached pressure-quantized [Path] batches so rendering avoids looping
  /// through hundreds of individual segments on every pan/zoom frame.
  List<StrokePathBatch> getPathBatches() {
    if (_cachedPathBatches != null && _cachedForWidth == strokeWidth) {
      return _cachedPathBatches!;
    }
    final batches = buildStrokePathBatches(points, strokeWidth);
    _cachedPathBatches = batches;
    _cachedForWidth = strokeWidth;
    return batches;
  }

  static List<StrokePathBatch> buildStrokePathBatches(
    List<StrokePoint> points,
    double baseWidth,
  ) {
    if (points.length < 2) return const <StrokePathBatch>[];

    final batches = <StrokePathBatch>[];
    double? currentBucketWidth;
    Path? currentPath;
    Offset? lastEnd;

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final avgPressure = (p1.pressure + p2.pressure) * 0.5;
      final pressureScale = (avgPressure > 0.0 && avgPressure != 1.0)
          ? (0.75 + 0.5 * avgPressure.clamp(0.0, 1.0))
          : 1.0;
      final rawW = math.max(0.5, baseWidth * pressureScale);
      // Quantize width to 0.25 px steps so neighboring segments merge into shared Paths
      final bucketW = (rawW * 4.0).round() / 4.0;

      if (currentPath == null || currentBucketWidth != bucketW) {
        if (currentPath != null && currentBucketWidth != null) {
          batches.add(StrokePathBatch(currentBucketWidth, currentPath));
        }
        currentBucketWidth = bucketW;
        currentPath = Path()..moveTo(p1.offset.dx, p1.offset.dy);
        currentPath.lineTo(p2.offset.dx, p2.offset.dy);
      } else {
        if (lastEnd != p1.offset) {
          currentPath.moveTo(p1.offset.dx, p1.offset.dy);
        }
        currentPath.lineTo(p2.offset.dx, p2.offset.dy);
      }
      lastEnd = p2.offset;
    }

    if (currentPath != null && currentBucketWidth != null) {
      batches.add(StrokePathBatch(currentBucketWidth, currentPath));
    }
    return batches;
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

  void translate(Offset delta) {
    if (delta == Offset.zero) return;
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      points[i] = StrokePoint(
        offset: p.offset + delta,
        pressure: p.pressure,
      );
    }
    if (_cachedBounds != null) {
      _cachedBounds = _cachedBounds!.shift(delta);
    }
    final batches = _cachedPathBatches;
    if (batches != null) {
      _cachedPathBatches = [
        for (final batch in batches)
          StrokePathBatch(batch.strokeWidth, batch.path.shift(delta)),
      ];
    }
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
  }) : id = id ?? nextAnnotationId('sh');
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

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../controllers/drawing_controller.dart';
import '../../models/editor_models.dart';

class PagePictureEntry {
  final Rect bounds;
  final ui.Picture picture;

  const PagePictureEntry(this.bounds, this.picture);
}

class SavedLayerPictureCache {
  Map<int, PagePictureEntry> _entries = {};
  DrawingController? _builtForController;
  int _version = 0;
  int _builtVersion = -1;

  void invalidate() {
    _version++;
    _disposePictures();
  }

  void _disposePictures() {
    if (_entries.isNotEmpty) {
      for (final entry in _entries.values) {
        entry.picture.dispose();
      }
      _entries = {};
    }
    _builtVersion = -1;
  }

  Map<int, PagePictureEntry> getOrBuild(DrawingController controller) {
    if (_builtForController == controller && _builtVersion == _version) {
      return _entries;
    }

    _disposePictures();
    _builtForController = controller;
    _builtVersion = _version;

    if (controller.strokes.isEmpty && controller.textAnnotations.isEmpty) {
      return _entries;
    }

    final annotationsByPage = <int, List<DrawnTextAnnotation>>{};
    final strokesByPage = <int, List<DrawingStroke>>{};
    final pageBounds = <int, Rect>{};

    void expandPageBounds(int page, Rect r) {
      final prev = pageBounds[page];
      pageBounds[page] = prev == null ? r : prev.expandToInclude(r);
    }

    for (final ta in controller.textAnnotations) {
      annotationsByPage.putIfAbsent(ta.pageNumber, () => []).add(ta);
      expandPageBounds(ta.pageNumber, ta.getBounds().inflate(4.0));
    }

    for (final st in controller.strokes) {
      strokesByPage.putIfAbsent(st.pageNumber, () => []).add(st);
      expandPageBounds(st.pageNumber, st.getBounds().inflate(st.strokeWidth + 8.0));
    }

    final highlightPaint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.multiply;
    final underlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final strikePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final strokePaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()..style = PaintingStyle.fill;

    final nextEntries = <int, PagePictureEntry>{};
    for (final pageNumber in pageBounds.keys) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final pageAnnotations = annotationsByPage[pageNumber];
      if (pageAnnotations != null) {
        for (final ta in pageAnnotations) {
          switch (ta.type) {
            case TextAnnotationType.highlight:
              highlightPaint.color = ta.color.withValues(alpha: 0.38);
              for (final rect in ta.rects) {
                canvas.drawRect(rect, highlightPaint);
              }
              break;
            case TextAnnotationType.underline:
              underlinePaint.color = ta.color;
              for (final rect in ta.rects) {
                canvas.drawLine(rect.bottomLeft, rect.bottomRight, underlinePaint);
              }
              break;
            case TextAnnotationType.strikethrough:
              strikePaint.color = ta.color;
              for (final rect in ta.rects) {
                final midY = (rect.top + rect.bottom) * 0.5;
                canvas.drawLine(Offset(rect.left, midY), Offset(rect.right, midY), strikePaint);
              }
              break;
          }
        }
      }

      final pageStrokes = strokesByPage[pageNumber];
      if (pageStrokes != null) {
        for (final st in pageStrokes) {
          if (st.points.isEmpty) continue;
          if (st.points.length == 1) {
            dotPaint.color = st.color;
            final p = st.points.first;
            final r = math.max(0.5, (st.strokeWidth * p.pressure) * 0.5);
            canvas.drawCircle(p.offset, r, dotPaint);
            continue;
          }
          strokePaint.color = st.color;
          final batches = st.getPathBatches();
          for (final batch in batches) {
            strokePaint.strokeWidth = batch.strokeWidth;
            canvas.drawPath(batch.path, strokePaint);
          }
        }
      }

      nextEntries[pageNumber] = PagePictureEntry(
        pageBounds[pageNumber]!,
        recorder.endRecording(),
      );
    }

    _entries = nextEntries;
    return _entries;
  }

  void dispose() {
    _disposePictures();
    _builtForController = null;
  }
}

void paintStrokePoints(Canvas canvas, List<StrokePoint> points, Color color, double baseWidth) {
  if (points.isEmpty) return;
  if (points.length == 1) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final r = math.max(0.5, (baseWidth * points.first.pressure) * 0.5);
    canvas.drawCircle(points.first.offset, r, paint);
    return;
  }

  final paint = Paint()
    ..color = color
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  final batches = DrawingStroke.buildStrokePathBatches(points, baseWidth);
  for (final batch in batches) {
    paint.strokeWidth = batch.strokeWidth;
    canvas.drawPath(batch.path, paint);
  }
}

class SavedAnnotationsPainter extends CustomPainter {
  final DrawingController controller;
  final SavedLayerPictureCache pictureCache;
  final TransformationController? transformationController;
  final String? selectedStrokeId;
  final String? selectedTextAnnotationId;

  SavedAnnotationsPainter({
    required super.repaint,
    required this.controller,
    required this.pictureCache,
    this.transformationController,
    this.selectedStrokeId,
    this.selectedTextAnnotationId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (controller.strokes.isEmpty && controller.textAnnotations.isEmpty) {
      return;
    }

    final tc = transformationController;
    final Rect visibleDocRect;
    if (tc != null) {
      final p1 = tc.toScene(Offset.zero);
      final p2 = tc.toScene(Offset(size.width, size.height));
      visibleDocRect = Rect.fromPoints(p1, p2).inflate(48.0);
      canvas.save();
      canvas.transform(tc.value.storage);
    } else {
      visibleDocRect = (Offset.zero & size).inflate(48.0);
    }

    // 1. Replay per-page pre-recorded Pictures for O(visible pages) rendering during pan/zoom
    final entries = pictureCache.getOrBuild(controller);
    for (final entry in entries.values) {
      if (entry.bounds.overlaps(visibleDocRect)) {
        canvas.drawPicture(entry.picture);
      }
    }

    // 2. Render selection highlights on top without invalidating Picture cache
    if (selectedTextAnnotationId != null) {
      for (final ta in controller.textAnnotations) {
        if (ta.id == selectedTextAnnotationId) {
          final selPaint = Paint()
            ..color = const Color(0xFF1E88E5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = ta.type == TextAnnotationType.highlight ? 1.5 : 1.0;
          final pad = ta.type == TextAnnotationType.highlight ? 1.5 : 2.0;
          for (final rect in ta.rects) {
            canvas.drawRect(rect.inflate(pad), selPaint);
          }
          break;
        }
      }
    }

    if (selectedStrokeId != null) {
      for (final stroke in controller.strokes) {
        if (stroke.id == selectedStrokeId) {
          final glowPaint = Paint()
            ..color = const Color(0xFF1E88E5).withValues(alpha: 0.38)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;
          for (final batch in stroke.getPathBatches()) {
            glowPaint.strokeWidth = batch.strokeWidth + 10.0;
            canvas.drawPath(batch.path, glowPaint);
          }
          final bounds = stroke.getBounds().inflate(6.0 + stroke.strokeWidth * 0.5);
          final boxPaint = Paint()
            ..color = const Color(0xFF1E88E5).withValues(alpha: 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2;
          canvas.drawRRect(RRect.fromRectAndRadius(bounds, const Radius.circular(8)), boxPaint);
          break;
        }
      }
    }

    if (tc != null) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant SavedAnnotationsPainter oldDelegate) {
    return oldDelegate.selectedStrokeId != selectedStrokeId ||
        oldDelegate.selectedTextAnnotationId != selectedTextAnnotationId ||
        oldDelegate.transformationController != transformationController ||
        oldDelegate.pictureCache != pictureCache ||
        oldDelegate.controller != controller;
  }
}

class ActiveAnnotationPainter extends CustomPainter {
  final DrawingController controller;
  final TransformationController? transformationController;
  final Color currentColor;
  final double currentStrokeWidth;
  final ShapeType shapeType;

  ActiveAnnotationPainter({
    required super.repaint,
    required this.controller,
    this.transformationController,
    required this.currentColor,
    required this.currentStrokeWidth,
    required this.shapeType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hasStroke = controller.activeStrokePoints != null &&
        controller.activeStrokePoints!.isNotEmpty;
    final hasShape = controller.activeShapeStart != null &&
        controller.activeShapeEnd != null;
    if (!hasStroke && !hasShape) {
      return;
    }

    final tc = transformationController;
    if (tc != null) {
      canvas.save();
      canvas.transform(tc.value.storage);
    }

    if (hasStroke) {
      paintStrokePoints(
        canvas,
        controller.activeStrokePoints!,
        currentColor,
        currentStrokeWidth,
      );
    }

    if (hasShape) {
      _drawShapePreview(
        canvas,
        shapeType,
        controller.activeShapeStart!,
        controller.activeShapeEnd!,
        currentColor,
        currentStrokeWidth,
      );
    }

    if (tc != null) {
      canvas.restore();
    }
  }

  void _drawShapePreview(
    Canvas canvas,
    ShapeType type,
    Offset start,
    Offset end,
    Color color,
    double strokeWidth,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    paintShapeOnCanvas(canvas, type, start, end, paint);
  }

  @override
  bool shouldRepaint(covariant ActiveAnnotationPainter oldDelegate) {
    return oldDelegate.currentColor != currentColor ||
        oldDelegate.currentStrokeWidth != currentStrokeWidth ||
        oldDelegate.shapeType != shapeType ||
        oldDelegate.transformationController != transformationController ||
        oldDelegate.controller != controller;
  }
}

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
  int _builtEpoch = -1;
  Map<int, int> _builtPageVersions = {};

  static final Paint _highlightPaint = Paint()
    ..style = PaintingStyle.fill
    ..blendMode = BlendMode.multiply;
  static final Paint _underlinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  static final Paint _strikePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8;
  static final Paint _strokePaint = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  static final Paint _dotPaint = Paint()..style = PaintingStyle.fill;

  void invalidate() {
    _disposePictures();
  }

  void _disposePictures() {
    if (_entries.isNotEmpty) {
      for (final entry in _entries.values) {
        entry.picture.dispose();
      }
      _entries = {};
    }
    _builtEpoch = -1;
    _builtPageVersions = {};
  }

  PagePictureEntry? _recordPageEntry(
    List<DrawnTextAnnotation>? pageAnnotations,
    List<DrawingStroke>? pageStrokes,
  ) {
    Rect? bounds;
    void expand(Rect r) {
      bounds = bounds == null ? r : bounds!.expandToInclude(r);
    }

    if (pageAnnotations != null) {
      for (final ta in pageAnnotations) {
        expand(ta.getBounds().inflate(4.0));
      }
    }
    if (pageStrokes != null) {
      for (final st in pageStrokes) {
        if (st.points.isNotEmpty) {
          expand(st.getBounds().inflate(st.strokeWidth + 8.0));
        }
      }
    }
    if (bounds == null) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (pageAnnotations != null) {
      for (final ta in pageAnnotations) {
        switch (ta.type) {
          case TextAnnotationType.highlight:
            _highlightPaint.color = ta.color.withValues(alpha: 0.38);
            for (final rect in ta.rects) {
              canvas.drawRect(rect, _highlightPaint);
            }
            break;
          case TextAnnotationType.underline:
            _underlinePaint.color = ta.color;
            for (final rect in ta.rects) {
              canvas.drawLine(rect.bottomLeft, rect.bottomRight, _underlinePaint);
            }
            break;
          case TextAnnotationType.strikethrough:
            _strikePaint.color = ta.color;
            for (final rect in ta.rects) {
              final midY = (rect.top + rect.bottom) * 0.5;
              canvas.drawLine(Offset(rect.left, midY), Offset(rect.right, midY), _strikePaint);
            }
            break;
        }
      }
    }

    if (pageStrokes != null) {
      for (final st in pageStrokes) {
        if (st.points.isEmpty) continue;
        if (st.points.length == 1) {
          _dotPaint.color = st.color;
          final p = st.points.first;
          final r = math.max(0.5, (st.strokeWidth * p.pressure) * 0.5);
          canvas.drawCircle(p.offset, r, _dotPaint);
          continue;
        }
        _strokePaint.color = st.color;
        final batches = st.getPathBatches();
        for (final batch in batches) {
          _strokePaint.strokeWidth = batch.strokeWidth;
          canvas.drawPath(batch.path, _strokePaint);
        }
      }
    }

    return PagePictureEntry(bounds!, recorder.endRecording());
  }

  Map<int, PagePictureEntry> getOrBuild(DrawingController controller) {
    final fullRebuild =
        !identical(_builtForController, controller) ||
        _builtEpoch != controller.savedEpoch;

    if (fullRebuild) {
      _disposePictures();
      _builtForController = controller;
      _builtEpoch = controller.savedEpoch;
      _builtPageVersions = Map<int, int>.of(controller.savedPageVersions);

      if (controller.strokes.isEmpty && controller.textAnnotations.isEmpty) {
        return _entries;
      }

      final annotationsByPage = <int, List<DrawnTextAnnotation>>{};
      final strokesByPage = <int, List<DrawingStroke>>{};
      final pages = <int>{};

      for (final ta in controller.textAnnotations) {
        annotationsByPage.putIfAbsent(ta.pageNumber, () => []).add(ta);
        pages.add(ta.pageNumber);
      }
      for (final st in controller.strokes) {
        strokesByPage.putIfAbsent(st.pageNumber, () => []).add(st);
        pages.add(st.pageNumber);
      }

      final nextEntries = <int, PagePictureEntry>{};
      for (final pageNumber in pages) {
        final entry = _recordPageEntry(
          annotationsByPage[pageNumber],
          strokesByPage[pageNumber],
        );
        if (entry != null) {
          nextEntries[pageNumber] = entry;
        }
      }
      _entries = nextEntries;
      return _entries;
    }

    // Incremental per-page rebuild: only touch pages whose revision changed.
    final currentVersions = controller.savedPageVersions;
    Set<int>? dirtyPages;
    for (final e in currentVersions.entries) {
      if (_builtPageVersions[e.key] != e.value) {
        (dirtyPages ??= <int>{}).add(e.key);
      }
    }
    if (dirtyPages == null) {
      return _entries;
    }

    final annotationsByPage = <int, List<DrawnTextAnnotation>>{};
    final strokesByPage = <int, List<DrawingStroke>>{};
    for (final ta in controller.textAnnotations) {
      if (dirtyPages.contains(ta.pageNumber)) {
        annotationsByPage.putIfAbsent(ta.pageNumber, () => []).add(ta);
      }
    }
    for (final st in controller.strokes) {
      if (dirtyPages.contains(st.pageNumber)) {
        strokesByPage.putIfAbsent(st.pageNumber, () => []).add(st);
      }
    }

    for (final pageNumber in dirtyPages) {
      _entries.remove(pageNumber)?.picture.dispose();
      final entry = _recordPageEntry(
        annotationsByPage[pageNumber],
        strokesByPage[pageNumber],
      );
      if (entry != null) {
        _entries[pageNumber] = entry;
      }
      _builtPageVersions[pageNumber] = currentVersions[pageNumber] ?? 0;
    }

    return _entries;
  }

  void dispose() {
    _disposePictures();
    _builtForController = null;
  }
}

final Paint _activeDotPaint = Paint()..style = PaintingStyle.fill;
final Paint _activeStrokePaint = Paint()
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..style = PaintingStyle.stroke;

void paintStrokePoints(Canvas canvas, List<StrokePoint> points, Color color, double baseWidth) {
  if (points.isEmpty) return;
  if (points.length == 1) {
    _activeDotPaint.color = color;
    final r = math.max(0.5, (baseWidth * points.first.pressure) * 0.5);
    canvas.drawCircle(points.first.offset, r, _activeDotPaint);
    return;
  }

  _activeStrokePaint.color = color;
  final batches = DrawingStroke.buildStrokePathBatches(points, baseWidth);
  for (final batch in batches) {
    _activeStrokePaint.strokeWidth = batch.strokeWidth;
    canvas.drawPath(batch.path, _activeStrokePaint);
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
    final selectedTa = controller.findTextAnnotationById(selectedTextAnnotationId);
    if (selectedTa != null) {
      final selPaint = Paint()
        ..color = const Color(0xFF1E88E5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selectedTa.type == TextAnnotationType.highlight ? 1.5 : 1.0;
      final pad = selectedTa.type == TextAnnotationType.highlight ? 1.5 : 2.0;
      for (final rect in selectedTa.rects) {
        canvas.drawRect(rect.inflate(pad), selPaint);
      }
    }

    final selectedStroke = controller.findStrokeById(selectedStrokeId);
    if (selectedStroke != null) {
      final glowPaint = Paint()
        ..color = const Color(0xFF1E88E5).withValues(alpha: 0.38)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      for (final batch in selectedStroke.getPathBatches()) {
        glowPaint.strokeWidth = batch.strokeWidth + 10.0;
        canvas.drawPath(batch.path, glowPaint);
      }
      final bounds = selectedStroke.getBounds().inflate(6.0 + selectedStroke.strokeWidth * 0.5);
      final boxPaint = Paint()
        ..color = const Color(0xFF1E88E5).withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawRRect(RRect.fromRectAndRadius(bounds, const Radius.circular(8)), boxPaint);
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

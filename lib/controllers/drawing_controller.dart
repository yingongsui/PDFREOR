import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/editor_models.dart';

enum _UndoActionType {
  addStroke,
  addShape,
  addTextBox,
  addImage,
  addTextAnnotation,
  removeStroke,
  removeShape,
  removeImage,
  removeTextAnnotation,
  modifyShape,
}

class _ShapeChange {
  final DrawnShape shape;
  final Offset oldStart;
  final Offset oldEnd;
  final Offset newStart;
  final Offset newEnd;

  _ShapeChange(this.shape, this.oldStart, this.oldEnd, this.newStart, this.newEnd);
}

class _UndoAction {
  final _UndoActionType type;
  final dynamic data;

  _UndoAction(this.type, this.data);
}

class DrawingController extends ChangeNotifier {
  final List<DrawingStroke> _strokes = [];
  final List<DrawnShape> _shapes = [];
  final List<DrawnTextBox> _textBoxes = [];
  final List<DrawnImage> _images = [];
  final List<DrawnTextAnnotation> _textAnnotations = [];
  final List<_UndoAction> _undoHistory = [];

  // Active stroke / shape currently being drawn
  List<StrokePoint>? _activeStrokePoints;
  Offset? _activeShapeStart;
  Offset? _activeShapeEnd;
  bool _isDirty = false;

  List<DrawingStroke> get strokes => List.unmodifiable(_strokes);
  List<DrawnShape> get shapes => List.unmodifiable(_shapes);
  List<DrawnTextBox> get textBoxes => List.unmodifiable(_textBoxes);
  List<DrawnImage> get images => List.unmodifiable(_images);
  List<DrawnTextAnnotation> get textAnnotations => List.unmodifiable(_textAnnotations);

  List<StrokePoint>? get activeStrokePoints => _activeStrokePoints;
  Offset? get activeShapeStart => _activeShapeStart;
  Offset? get activeShapeEnd => _activeShapeEnd;

  bool get canUndo => _undoHistory.isNotEmpty;
  bool get hasAnnotations =>
      _strokes.isNotEmpty ||
      _shapes.isNotEmpty ||
      _textBoxes.isNotEmpty ||
      _images.isNotEmpty ||
      _textAnnotations.isNotEmpty;
  bool get hasUnsavedChanges => _isDirty && hasAnnotations;

  void markSaved() {
    _isDirty = false;
    notifyListeners();
  }

  // --- STROKE DRAWING ---

  void startStroke(Offset point, double pressure) {
    _activeStrokePoints = [
      StrokePoint(offset: point, pressure: pressure > 0 ? pressure : 1.0),
    ];
    notifyListeners();
  }

  void addStrokePoint(Offset point, double pressure) {
    if (_activeStrokePoints != null) {
      _activeStrokePoints!.add(
        StrokePoint(offset: point, pressure: pressure > 0 ? pressure : 1.0),
      );
      notifyListeners();
    }
  }

  void endStroke(Color color, double strokeWidth, int pageNumber) {
    if (_activeStrokePoints != null && _activeStrokePoints!.isNotEmpty) {
      final stroke = DrawingStroke(
        points: List.from(_activeStrokePoints!),
        color: color,
        strokeWidth: strokeWidth,
        pageNumber: pageNumber,
      );
      _strokes.add(stroke);
      _undoHistory.add(_UndoAction(_UndoActionType.addStroke, stroke));
      _isDirty = true;
    }
    _activeStrokePoints = null;
    notifyListeners();
  }

  void cancelActiveStroke() {
    if (_activeStrokePoints != null) {
      _activeStrokePoints = null;
      notifyListeners();
    }
  }

  // --- STROKE ERASER (Erases continuous stroke on touch) ---

  bool eraseAt(Offset point, [int? pageNumber, double radius = 22.0]) {
    bool erasedAny = false;

    // 1. Check strokes in reverse (topmost first)
    for (int i = _strokes.length - 1; i >= 0; i--) {
      final stroke = _strokes[i];
      if (pageNumber != null && stroke.pageNumber != pageNumber) continue;

      if (_hitTestStroke(stroke, point, radius + stroke.strokeWidth / 2)) {
        _undoHistory.add(_UndoAction(_UndoActionType.removeStroke, stroke));
        _strokes.removeAt(i);
        erasedAny = true;
      }
    }

    // 2. Check shapes
    for (int i = _shapes.length - 1; i >= 0; i--) {
      final shape = _shapes[i];
      if (pageNumber != null && shape.pageNumber != pageNumber) continue;

      if (_hitTestShape(shape, point, radius + shape.strokeWidth / 2)) {
        _undoHistory.add(_UndoAction(_UndoActionType.removeShape, shape));
        _shapes.removeAt(i);
        erasedAny = true;
      }
    }

    if (erasedAny) {
      _isDirty = hasAnnotations;
      notifyListeners();
    }
    return erasedAny;
  }

  bool _hitTestStroke(DrawingStroke stroke, Offset point, double threshold) {
    for (int i = 0; i < stroke.points.length; i++) {
      if ((stroke.points[i].offset - point).distance <= threshold) {
        return true;
      }
      if (i > 0) {
        final d = _distToSegment(point, stroke.points[i - 1].offset, stroke.points[i].offset);
        if (d <= threshold) return true;
      }
    }
    return false;
  }

  bool _hitTestShape(DrawnShape shape, Offset point, double threshold) {
    return isPointNearShape(point, shape, threshold);
  }

  static bool isPointNearShape(Offset point, DrawnShape shape, [double threshold = 24.0]) {
    final rect = Rect.fromPoints(shape.start, shape.end);
    switch (shape.type) {
      case ShapeType.rectangle:
        // Inside small rectangle or near perimeter of larger rectangle
        if (rect.inflate(threshold).contains(point)) {
          if (rect.width < 100 && rect.height < 100) return true;
          final l1 = _distToSegment(point, rect.topLeft, rect.topRight);
          final l2 = _distToSegment(point, rect.topRight, rect.bottomRight);
          final l3 = _distToSegment(point, rect.bottomRight, rect.bottomLeft);
          final l4 = _distToSegment(point, rect.bottomLeft, rect.topLeft);
          return math.min(math.min(l1, l2), math.min(l3, l4)) <= threshold;
        }
        return false;
      case ShapeType.circle:
        final center = rect.center;
        final r = math.max(rect.width, rect.height) / 2;
        final d = (point - center).distance;
        if (r < 50 && d <= r + threshold) return true;
        return (d - r).abs() <= threshold;
      case ShapeType.line:
      case ShapeType.arrow:
        return _distToSegment(point, shape.start, shape.end) <= threshold;
    }
  }

  DrawnShape? hitTestShape(Offset point, [double threshold = 24.0]) {
    for (int i = _shapes.length - 1; i >= 0; i--) {
      final shape = _shapes[i];
      if (isPointNearShape(point, shape, threshold)) {
        return shape;
      }
    }
    return null;
  }

  DrawingStroke? hitTestStroke(Offset point, [double threshold = 20.0]) {
    for (int i = _strokes.length - 1; i >= 0; i--) {
      final stroke = _strokes[i];
      if (_hitTestStroke(stroke, point, threshold + stroke.strokeWidth / 2)) {
        return stroke;
      }
    }
    return null;
  }

  void updateStroke(DrawingStroke stroke) {
    _isDirty = true;
    notifyListeners();
  }

  void deleteStroke(String id) {
    final idx = _strokes.indexWhere((s) => s.id == id);
    if (idx != -1) {
      final removed = _strokes.removeAt(idx);
      _undoHistory.add(_UndoAction(_UndoActionType.removeStroke, removed));
      _isDirty = hasAnnotations;
      notifyListeners();
    }
  }

  static double _distToSegment(Offset p, Offset v, Offset w) {
    final l2 = (v - w).distanceSquared;
    if (l2 == 0.0) return (p - v).distance;
    final t = math.max(
      0.0,
      math.min(1.0, ((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2),
    );
    final projection = Offset(v.dx + t * (w.dx - v.dx), v.dy + t * (w.dy - v.dy));
    return (p - projection).distance;
  }

  // --- SHAPE DRAWING ---

  void startShape(Offset point) {
    _activeShapeStart = point;
    _activeShapeEnd = point;
    notifyListeners();
  }

  void updateShape(Offset point) {
    _activeShapeEnd = point;
    notifyListeners();
  }

  void endShape(ShapeType type, Color color, double strokeWidth, int pageNumber) {
    if (_activeShapeStart != null && _activeShapeEnd != null) {
      final distance = (_activeShapeEnd! - _activeShapeStart!).distance;
      if (distance > 5) {
        final shape = DrawnShape(
          type: type,
          start: _activeShapeStart!,
          end: _activeShapeEnd!,
          color: color,
          strokeWidth: strokeWidth,
          pageNumber: pageNumber,
        );
        _shapes.add(shape);
        _undoHistory.add(_UndoAction(_UndoActionType.addShape, shape));
        _isDirty = true;
      }
    }
    _activeShapeStart = null;
    _activeShapeEnd = null;
    notifyListeners();
  }

  void updateDrawnShape(DrawnShape updated) {
    final idx = _shapes.indexWhere((s) => s.id == updated.id);
    if (idx != -1) {
      _shapes[idx] = updated;
      _isDirty = true;
      notifyListeners();
    }
  }

  void deleteDrawnShape(String id) {
    final idx = _shapes.indexWhere((s) => s.id == id);
    if (idx != -1) {
      final removed = _shapes.removeAt(idx);
      _undoHistory.add(_UndoAction(_UndoActionType.removeShape, removed));
      _isDirty = hasAnnotations;
      notifyListeners();
    }
  }

  void recordShapeModification(DrawnShape shape, Offset oldStart, Offset oldEnd) {
    if (shape.start != oldStart || shape.end != oldEnd) {
      _undoHistory.add(_UndoAction(
        _UndoActionType.modifyShape,
        _ShapeChange(shape, oldStart, oldEnd, shape.start, shape.end),
      ));
      _isDirty = true;
      notifyListeners();
    }
  }

  // --- TEXT BOXES ---

  void addTextBox(DrawnTextBox tb) {
    _textBoxes.add(tb);
    _undoHistory.add(_UndoAction(_UndoActionType.addTextBox, tb));
    _isDirty = true;
    notifyListeners();
  }

  void updateTextBox(DrawnTextBox updated) {
    final idx = _textBoxes.indexWhere((t) => t.id == updated.id);
    if (idx != -1) {
      _textBoxes[idx] = updated;
      _isDirty = true;
      notifyListeners();
    }
  }

  void deleteTextBox(String id) {
    _textBoxes.removeWhere((t) => t.id == id);
    _isDirty = hasAnnotations;
    notifyListeners();
  }

  // --- IMAGES ---

  void addImage(DrawnImage img) {
    _images.add(img);
    _undoHistory.add(_UndoAction(_UndoActionType.addImage, img));
    _isDirty = true;
    notifyListeners();
  }

  void updateImage(DrawnImage updated) {
    final idx = _images.indexWhere((i) => i.id == updated.id);
    if (idx != -1) {
      _images[idx] = updated;
      _isDirty = true;
      notifyListeners();
    }
  }

  void deleteImage(String id) {
    final idx = _images.indexWhere((i) => i.id == id);
    if (idx != -1) {
      final removed = _images.removeAt(idx);
      _undoHistory.add(_UndoAction(_UndoActionType.removeImage, removed));
      _isDirty = hasAnnotations;
      notifyListeners();
    }
  }

  // --- TEXT ANNOTATIONS (HIGHLIGHT, UNDERLINE, STRIKETHROUGH) ---

  void addTextAnnotation(DrawnTextAnnotation ta) {
    _textAnnotations.add(ta);
    _undoHistory.add(_UndoAction(_UndoActionType.addTextAnnotation, ta));
    _isDirty = true;
    notifyListeners();
  }

  void updateTextAnnotation(DrawnTextAnnotation updated) {
    final idx = _textAnnotations.indexWhere((a) => a.id == updated.id);
    if (idx != -1) {
      _textAnnotations[idx] = updated;
      _isDirty = true;
      notifyListeners();
    }
  }

  void deleteTextAnnotation(String id) {
    final idx = _textAnnotations.indexWhere((a) => a.id == id);
    if (idx != -1) {
      final removed = _textAnnotations.removeAt(idx);
      _undoHistory.add(_UndoAction(_UndoActionType.removeTextAnnotation, removed));
      _isDirty = hasAnnotations;
      notifyListeners();
    }
  }

  DrawnTextAnnotation? hitTestTextAnnotation(Offset point, double tolerance) {
    for (int i = _textAnnotations.length - 1; i >= 0; i--) {
      final ta = _textAnnotations[i];
      for (final rect in ta.rects) {
        if (rect.inflate(tolerance).contains(point)) {
          return ta;
        }
      }
    }
    return null;
  }

  // --- UNDO ---

  void undo() {
    if (_undoHistory.isEmpty) return;
    final action = _undoHistory.removeLast();
    switch (action.type) {
      case _UndoActionType.addStroke:
        _strokes.remove(action.data);
        break;
      case _UndoActionType.addShape:
        _shapes.remove(action.data);
        break;
      case _UndoActionType.addTextBox:
        _textBoxes.remove(action.data);
        break;
      case _UndoActionType.addImage:
        _images.remove(action.data);
        break;
      case _UndoActionType.addTextAnnotation:
        _textAnnotations.remove(action.data);
        break;
      case _UndoActionType.removeStroke:
        _strokes.add(action.data);
        break;
      case _UndoActionType.removeShape:
        _shapes.add(action.data);
        break;
      case _UndoActionType.removeImage:
        _images.add(action.data);
        break;
      case _UndoActionType.removeTextAnnotation:
        _textAnnotations.add(action.data);
        break;
      case _UndoActionType.modifyShape:
        final change = action.data as _ShapeChange;
        change.shape.start = change.oldStart;
        change.shape.end = change.oldEnd;
        break;
    }
    _isDirty = hasAnnotations;
    notifyListeners();
  }

  void clearAll() {
    _strokes.clear();
    _shapes.clear();
    _textBoxes.clear();
    _images.clear();
    _textAnnotations.clear();
    _undoHistory.clear();
    _activeStrokePoints = null;
    _activeShapeStart = null;
    _activeShapeEnd = null;
    _isDirty = false;
    notifyListeners();
  }
}


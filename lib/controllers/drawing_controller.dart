import 'dart:collection';
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
  removeTextBox,
  removeImage,
  removeTextAnnotation,
  modifyShape,
  modifyImage,
  modifyTextBoxLayout,
  modifyStrokeMove,
}

class _StrokeMoveChange {
  final DrawingStroke stroke;
  final Offset delta;

  const _StrokeMoveChange(this.stroke, this.delta);
}

class _RemovedEntry {
  final int index;
  final dynamic item;

  const _RemovedEntry(this.index, this.item);
}

class _ShapeChange {
  final DrawnShape shape;
  Offset oldStart;
  Offset oldEnd;
  Offset newStart;
  Offset newEnd;

  _ShapeChange(this.shape, this.oldStart, this.oldEnd, this.newStart, this.newEnd);
}

class _ImageChange {
  final DrawnImage image;
  Offset oldPosition;
  double oldWidth;
  double oldHeight;
  Offset newPosition;
  double newWidth;
  double newHeight;

  _ImageChange(
    this.image,
    this.oldPosition,
    this.oldWidth,
    this.oldHeight,
    this.newPosition,
    this.newWidth,
    this.newHeight,
  );
}

class _TextBoxLayoutChange {
  final DrawnTextBox textBox;
  Offset oldPosition;
  double? oldWidth;
  Offset newPosition;
  double? newWidth;

  _TextBoxLayoutChange(
    this.textBox,
    this.oldPosition,
    this.oldWidth,
    this.newPosition,
    this.newWidth,
  );
}

class _LayerNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _UndoAction {
  final _UndoActionType type;
  final dynamic data;

  _UndoAction(this.type, this.data);
}

class DrawingController extends ChangeNotifier {
  static const int _maxUndoHistory = 120;
  static const double _minStrokePointDistanceSq = 0.1225; // ~0.35 doc px

  final List<DrawingStroke> _strokes = [];
  final List<DrawnShape> _shapes = [];
  final List<DrawnTextBox> _textBoxes = [];
  final List<DrawnImage> _images = [];
  final List<DrawnTextAnnotation> _textAnnotations = [];
  final List<_UndoAction> _undoHistory = [];

  final _LayerNotifier _savedLayerNotifier = _LayerNotifier();
  final _LayerNotifier _activeLayerNotifier = _LayerNotifier();

  /// Repaint listenable exclusively for committed strokes and text annotations.
  Listenable get savedLayerListenable => _savedLayerNotifier;

  /// Repaint listenable exclusively for high-frequency active stroke/shape previews.
  Listenable get activeLayerListenable => _activeLayerNotifier;

  // Active stroke / shape currently being drawn
  List<StrokePoint>? _activeStrokePoints;
  Offset? _activeShapeStart;
  Offset? _activeShapeEnd;
  bool _isDirty = false;
  bool _hasSavedBaseline = false;

  late final UnmodifiableListView<DrawingStroke> _strokesView = UnmodifiableListView(_strokes);
  late final UnmodifiableListView<DrawnShape> _shapesView = UnmodifiableListView(_shapes);
  late final UnmodifiableListView<DrawnTextBox> _textBoxesView = UnmodifiableListView(_textBoxes);
  late final UnmodifiableListView<DrawnImage> _imagesView = UnmodifiableListView(_images);
  late final UnmodifiableListView<DrawnTextAnnotation> _textAnnotationsView =
      UnmodifiableListView(_textAnnotations);

  List<DrawingStroke> get strokes => _strokesView;
  List<DrawnShape> get shapes => _shapesView;
  List<DrawnTextBox> get textBoxes => _textBoxesView;
  List<DrawnImage> get images => _imagesView;
  List<DrawnTextAnnotation> get textAnnotations => _textAnnotationsView;

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
  bool get hasUnsavedChanges => _isDirty && (hasAnnotations || _hasSavedBaseline);

  void _pushUndo(_UndoAction action) {
    _undoHistory.add(action);
    if (_undoHistory.length > _maxUndoHistory) {
      _undoHistory.removeAt(0);
    }
  }

  void _notifyActiveOnly() {
    _activeLayerNotifier.notify();
    notifyListeners();
  }

  void _notifySavedOnly() {
    _savedLayerNotifier.notify();
    notifyListeners();
  }

  void _notifyBothLayers() {
    _savedLayerNotifier.notify();
    _activeLayerNotifier.notify();
    notifyListeners();
  }

  @override
  void dispose() {
    _savedLayerNotifier.dispose();
    _activeLayerNotifier.dispose();
    super.dispose();
  }

  void markSaved() {
    _hasSavedBaseline = hasAnnotations;
    _isDirty = false;
    notifyListeners();
  }

  // --- STROKE DRAWING ---

  void startStroke(Offset point, double pressure) {
    _activeShapeStart = null;
    _activeShapeEnd = null;
    _activeStrokePoints = [
      StrokePoint(offset: point, pressure: pressure > 0 ? pressure : 1.0),
    ];
    _notifyActiveOnly();
  }

  void addStrokePoint(Offset point, double pressure) {
    final active = _activeStrokePoints;
    if (active == null) return;
    if (active.isNotEmpty &&
        (point - active.last.offset).distanceSquared < _minStrokePointDistanceSq) {
      return;
    }
    active.add(
      StrokePoint(offset: point, pressure: pressure > 0 ? pressure : 1.0),
    );
    _notifyActiveOnly();
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
      _pushUndo(_UndoAction(_UndoActionType.addStroke, stroke));
      _isDirty = true;
    }
    _activeStrokePoints = null;
    _notifyBothLayers();
  }

  void cancelActiveStroke() {
    if (_activeStrokePoints != null) {
      _activeStrokePoints = null;
      _notifyActiveOnly();
    }
  }

  // --- STROKE ERASER (Erases continuous stroke on touch) ---

  bool eraseAt(Offset point, [int? pageNumber, double radius = 22.0]) {
    bool erasedStrokes = false;
    bool erasedShapes = false;

    // 1. Check strokes in reverse (topmost first)
    for (int i = _strokes.length - 1; i >= 0; i--) {
      final stroke = _strokes[i];
      if (pageNumber != null && stroke.pageNumber != pageNumber) continue;

      if (_hitTestStroke(stroke, point, radius + stroke.strokeWidth / 2)) {
        _pushUndo(_UndoAction(_UndoActionType.removeStroke, _RemovedEntry(i, stroke)));
        _strokes.removeAt(i);
        erasedStrokes = true;
      }
    }

    // 2. Check shapes
    for (int i = _shapes.length - 1; i >= 0; i--) {
      final shape = _shapes[i];
      if (pageNumber != null && shape.pageNumber != pageNumber) continue;

      if (isPointNearShape(point, shape, radius + shape.strokeWidth / 2)) {
        _pushUndo(_UndoAction(_UndoActionType.removeShape, _RemovedEntry(i, shape)));
        _shapes.removeAt(i);
        erasedShapes = true;
      }
    }

    if (erasedStrokes || erasedShapes) {
      _isDirty = hasAnnotations || _hasSavedBaseline;
      if (erasedStrokes) {
        _savedLayerNotifier.notify();
      }
      notifyListeners();
    }
    return erasedStrokes || erasedShapes;
  }

  bool _hitTestStroke(DrawingStroke stroke, Offset point, double threshold) {
    if (!stroke.getBounds().inflate(threshold).contains(point)) {
      return false;
    }
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

  static bool isPointNearShape(Offset point, DrawnShape shape, [double threshold = 24.0]) {
    final rect = Rect.fromPoints(shape.start, shape.end);
    if (!rect.inflate(threshold).contains(point)) {
      return false;
    }
    switch (shape.type) {
      case ShapeType.rectangle:
        // Inside small rectangle or near perimeter
        if (rect.width < 100 && rect.height < 100 && rect.contains(point)) {
          return true;
        }
        final l1 = _distToSegment(point, rect.topLeft, rect.topRight);
        final l2 = _distToSegment(point, rect.topRight, rect.bottomRight);
        final l3 = _distToSegment(point, rect.bottomRight, rect.bottomLeft);
        final l4 = _distToSegment(point, rect.bottomLeft, rect.topLeft);
        return math.min(math.min(l1, l2), math.min(l3, l4)) <= threshold;
      case ShapeType.roundedRectangle:
        final radius = roundedRectCornerRadius(rect);
        final halfW = rect.width * 0.5;
        final halfH = rect.height * 0.5;
        final center = rect.center;
        final qx = (point.dx - center.dx).abs() - (halfW - radius);
        final qy = (point.dy - center.dy).abs() - (halfH - radius);
        final outsideX = math.max(qx, 0.0);
        final outsideY = math.max(qy, 0.0);
        final outsideDist = math.sqrt(outsideX * outsideX + outsideY * outsideY);
        final insideDist = math.min(math.max(qx, qy), 0.0);
        final signedDist = outsideDist + insideDist - radius;
        if (rect.width < 100 && rect.height < 100 && signedDist <= threshold) {
          return true;
        }
        return signedDist.abs() <= threshold;
      case ShapeType.circle:
        final center = rect.center;
        final rx = rect.width / 2;
        final ry = rect.height / 2;
        final dx = (point.dx - center.dx).abs();
        final dy = (point.dy - center.dy).abs();
        final outerRx = math.max(rx + threshold, 1.0);
        final outerRy = math.max(ry + threshold, 1.0);
        final outerNorm = (dx * dx) / (outerRx * outerRx) + (dy * dy) / (outerRy * outerRy);
        if (outerNorm > 1.0) return false;
        if (rx < 50 && ry < 50) return true;
        if (rx <= threshold || ry <= threshold) return true;
        final innerRx = rx - threshold;
        final innerRy = ry - threshold;
        final innerNorm = (dx * dx) / (innerRx * innerRx) + (dy * dy) / (innerRy * innerRy);
        return innerNorm >= 1.0;
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
    stroke.invalidateBounds();
    _isDirty = true;
    _notifySavedOnly();
  }

  void moveStroke(DrawingStroke stroke, Offset delta) {
    if (delta == Offset.zero) return;
    stroke.translate(delta);
    _isDirty = true;
    _notifySavedOnly();
  }

  void recordStrokeMove(DrawingStroke stroke, Offset totalDelta) {
    if (totalDelta == Offset.zero) return;
    _pushUndo(_UndoAction(
      _UndoActionType.modifyStrokeMove,
      _StrokeMoveChange(stroke, totalDelta),
    ));
    _isDirty = true;
    notifyListeners();
  }

  void deleteStroke(String id) {
    final idx = _strokes.indexWhere((s) => s.id == id);
    if (idx != -1) {
      final removed = _strokes.removeAt(idx);
      _pushUndo(_UndoAction(_UndoActionType.removeStroke, _RemovedEntry(idx, removed)));
      _isDirty = hasAnnotations || _hasSavedBaseline;
      _notifySavedOnly();
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
    _activeStrokePoints = null;
    _activeShapeStart = point;
    _activeShapeEnd = point;
    _notifyActiveOnly();
  }

  void updateShape(Offset point) {
    _activeShapeEnd = point;
    _notifyActiveOnly();
  }

  void cancelActiveShape() {
    if (_activeShapeStart != null || _activeShapeEnd != null) {
      _activeShapeStart = null;
      _activeShapeEnd = null;
      _notifyActiveOnly();
    }
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
        _pushUndo(_UndoAction(_UndoActionType.addShape, shape));
        _isDirty = true;
      }
    }
    _activeShapeStart = null;
    _activeShapeEnd = null;
    _notifyActiveOnly();
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
      _pushUndo(_UndoAction(_UndoActionType.removeShape, _RemovedEntry(idx, removed)));
      _isDirty = hasAnnotations || _hasSavedBaseline;
      notifyListeners();
    }
  }

  void recordShapeModification(DrawnShape shape, Offset oldStart, Offset oldEnd) {
    if (shape.start != oldStart || shape.end != oldEnd) {
      _pushUndo(_UndoAction(
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
    _pushUndo(_UndoAction(_UndoActionType.addTextBox, tb));
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

  void recordTextBoxLayoutModification(
    DrawnTextBox tb,
    Offset oldPosition,
    double? oldWidth,
  ) {
    if (tb.position != oldPosition || tb.width != oldWidth) {
      _pushUndo(_UndoAction(
        _UndoActionType.modifyTextBoxLayout,
        _TextBoxLayoutChange(tb, oldPosition, oldWidth, tb.position, tb.width),
      ));
      _isDirty = true;
      notifyListeners();
    }
  }

  void deleteTextBox(String id) {
    final idx = _textBoxes.indexWhere((t) => t.id == id);
    if (idx != -1) {
      final removed = _textBoxes.removeAt(idx);
      // If an empty freshly created text box is cancelled without typing, drop its add action
      if (removed.text.trim().isEmpty &&
          _undoHistory.isNotEmpty &&
          _undoHistory.last.type == _UndoActionType.addTextBox &&
          identical(_undoHistory.last.data, removed)) {
        _undoHistory.removeLast();
      } else {
        _pushUndo(_UndoAction(_UndoActionType.removeTextBox, _RemovedEntry(idx, removed)));
      }
      _isDirty = hasAnnotations || _hasSavedBaseline;
      notifyListeners();
    }
  }

  // --- IMAGES ---

  void addImage(DrawnImage img) {
    _images.add(img);
    _pushUndo(_UndoAction(_UndoActionType.addImage, img));
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

  void recordImageModification(
    DrawnImage img,
    Offset oldPosition,
    double oldWidth,
    double oldHeight,
  ) {
    if (img.position != oldPosition || img.width != oldWidth || img.height != oldHeight) {
      _pushUndo(_UndoAction(
        _UndoActionType.modifyImage,
        _ImageChange(img, oldPosition, oldWidth, oldHeight, img.position, img.width, img.height),
      ));
      _isDirty = true;
      notifyListeners();
    }
  }

  void deleteImage(String id) {
    final idx = _images.indexWhere((i) => i.id == id);
    if (idx != -1) {
      final removed = _images.removeAt(idx);
      _pushUndo(_UndoAction(_UndoActionType.removeImage, _RemovedEntry(idx, removed)));
      _isDirty = hasAnnotations || _hasSavedBaseline;
      notifyListeners();
    }
  }

  // --- TEXT ANNOTATIONS (HIGHLIGHT, UNDERLINE, STRIKETHROUGH) ---

  void addTextAnnotation(DrawnTextAnnotation ta) {
    _textAnnotations.add(ta);
    _pushUndo(_UndoAction(_UndoActionType.addTextAnnotation, ta));
    _isDirty = true;
    _notifySavedOnly();
  }

  void updateTextAnnotation(DrawnTextAnnotation updated) {
    final idx = _textAnnotations.indexWhere((a) => a.id == updated.id);
    if (idx != -1) {
      _textAnnotations[idx] = updated;
      _isDirty = true;
      _notifySavedOnly();
    }
  }

  void deleteTextAnnotation(String id) {
    final idx = _textAnnotations.indexWhere((a) => a.id == id);
    if (idx != -1) {
      final removed = _textAnnotations.removeAt(idx);
      _pushUndo(
        _UndoAction(_UndoActionType.removeTextAnnotation, _RemovedEntry(idx, removed)),
      );
      _isDirty = hasAnnotations || _hasSavedBaseline;
      _notifySavedOnly();
    }
  }

  DrawnTextAnnotation? hitTestTextAnnotation(Offset point, double tolerance) {
    for (int i = _textAnnotations.length - 1; i >= 0; i--) {
      final ta = _textAnnotations[i];
      if (!ta.getBounds().inflate(tolerance).contains(point)) continue;
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
        _savedLayerNotifier.notify();
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
        _savedLayerNotifier.notify();
        break;
      case _UndoActionType.removeStroke:
        final entry = action.data as _RemovedEntry;
        _strokes.insert(entry.index.clamp(0, _strokes.length), entry.item as DrawingStroke);
        _savedLayerNotifier.notify();
        break;
      case _UndoActionType.removeShape:
        final entry = action.data as _RemovedEntry;
        _shapes.insert(entry.index.clamp(0, _shapes.length), entry.item as DrawnShape);
        break;
      case _UndoActionType.removeTextBox:
        final entry = action.data as _RemovedEntry;
        _textBoxes.insert(entry.index.clamp(0, _textBoxes.length), entry.item as DrawnTextBox);
        break;
      case _UndoActionType.removeImage:
        final entry = action.data as _RemovedEntry;
        _images.insert(entry.index.clamp(0, _images.length), entry.item as DrawnImage);
        break;
      case _UndoActionType.removeTextAnnotation:
        final entry = action.data as _RemovedEntry;
        _textAnnotations.insert(
          entry.index.clamp(0, _textAnnotations.length),
          entry.item as DrawnTextAnnotation,
        );
        _savedLayerNotifier.notify();
        break;
      case _UndoActionType.modifyShape:
        final change = action.data as _ShapeChange;
        change.shape.start = change.oldStart;
        change.shape.end = change.oldEnd;
        break;
      case _UndoActionType.modifyImage:
        final change = action.data as _ImageChange;
        change.image.position = change.oldPosition;
        change.image.width = change.oldWidth;
        change.image.height = change.oldHeight;
        break;
      case _UndoActionType.modifyTextBoxLayout:
        final change = action.data as _TextBoxLayoutChange;
        change.textBox.position = change.oldPosition;
        change.textBox.width = change.oldWidth;
        break;
      case _UndoActionType.modifyStrokeMove:
        final change = action.data as _StrokeMoveChange;
        change.stroke.translate(-change.delta);
        _savedLayerNotifier.notify();
        break;
    }
    _isDirty = hasAnnotations || _hasSavedBaseline;
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
    _hasSavedBaseline = false;
    _notifyBothLayers();
  }
}

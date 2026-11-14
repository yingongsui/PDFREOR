import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../controllers/drawing_controller.dart';
import '../../models/editor_models.dart';

const double kShapeCanvasPadding = 48.0;
const double kStrokeDragHitExtraPadding = 8.0;
const double kStrokeDragMinHalfExtent = 16.0;

Rect paddedShapeBounds(DrawnShape shape, [double padding = kShapeCanvasPadding]) {
  final minX = math.min(shape.start.dx, shape.end.dx) - padding;
  final maxX = math.max(shape.start.dx, shape.end.dx) + padding;
  final minY = math.min(shape.start.dy, shape.end.dy) - padding;
  final maxY = math.max(shape.start.dy, shape.end.dy) + padding;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

Rect paddedStrokeBounds(DrawingStroke stroke) {
  final padding = math.max(
    kStrokeDragMinHalfExtent,
    6.0 + stroke.strokeWidth * 0.5 + kStrokeDragHitExtraPadding,
  );
  return stroke.getBounds().inflate(padding);
}

class StylusDrawingGestureRecognizer extends OneSequenceGestureRecognizer {
  bool stylusOnly;
  bool isDrawingMode;
  EditorTool activeTool;
  ShapeType activeShape;
  Color activeColor;
  double activeStrokeWidth;
  int currentPage;
  int Function()? currentPageGetter;
  DrawingController controller;
  TransformationController? transformationController;
  bool isHardwareButtonPressed;
  ShapeType? oneShotShape;
  VoidCallback? onOneShotShapeCompleted;
  VoidCallback? onStylusDetected;
  VoidCallback? onStylusDrawStarted;
  VoidCallback? onShapeCompleted;
  String? selectedShapeId;
  String? selectedStrokeId;

  int? _activePointerId;

  StylusDrawingGestureRecognizer({
    required this.stylusOnly,
    required this.isDrawingMode,
    required this.activeTool,
    required this.activeShape,
    required this.activeColor,
    required this.activeStrokeWidth,
    required this.currentPage,
    this.currentPageGetter,
    required this.controller,
    this.transformationController,
    this.isHardwareButtonPressed = false,
    this.oneShotShape,
    this.onOneShotShapeCompleted,
    this.onStylusDetected,
    this.onStylusDrawStarted,
    this.onShapeCompleted,
    this.selectedShapeId,
    this.selectedStrokeId,
  });

  void update({
    required bool stylusOnly,
    required bool isDrawingMode,
    required EditorTool activeTool,
    required ShapeType activeShape,
    required Color activeColor,
    required double activeStrokeWidth,
    required int currentPage,
    int Function()? currentPageGetter,
    required DrawingController controller,
    TransformationController? transformationController,
    bool isHardwareButtonPressed = false,
    ShapeType? oneShotShape,
    VoidCallback? onOneShotShapeCompleted,
    VoidCallback? onStylusDetected,
    VoidCallback? onStylusDrawStarted,
    VoidCallback? onShapeCompleted,
    String? selectedShapeId,
    String? selectedStrokeId,
  }) {
    this.stylusOnly = stylusOnly;
    this.isDrawingMode = isDrawingMode;
    this.activeTool = activeTool;
    this.activeShape = activeShape;
    this.activeColor = activeColor;
    this.activeStrokeWidth = activeStrokeWidth;
    this.currentPage = currentPage;
    this.currentPageGetter = currentPageGetter;
    this.controller = controller;
    this.transformationController = transformationController;
    this.isHardwareButtonPressed = isHardwareButtonPressed;
    this.oneShotShape = oneShotShape;
    this.onOneShotShapeCompleted = onOneShotShapeCompleted;
    this.onStylusDetected = onStylusDetected;
    this.onStylusDrawStarted = onStylusDrawStarted;
    this.onShapeCompleted = onShapeCompleted;
    this.selectedShapeId = selectedShapeId;
    this.selectedStrokeId = selectedStrokeId;
  }

  bool _isStylus(PointerEvent event) {
    return event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
  }

  bool _isEraserActive(PointerEvent event) {
    if (activeTool == EditorTool.eraser) return true;
    if (isHardwareButtonPressed) return true;
    if ((event.buttons & kPrimaryStylusButton != 0) ||
        (event.buttons & kSecondaryStylusButton != 0) ||
        (event.buttons & kSecondaryMouseButton != 0)) {
      return true;
    }
    return false;
  }

  Offset _getDocPoint(Offset screenPoint) {
    if (transformationController != null) {
      return transformationController!.toScene(screenPoint);
    }
    return screenPoint;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_activePointerId != null) {
      return;
    }

    final isStylus = _isStylus(event);
    if (isStylus) {
      onStylusDetected?.call();
    }

    final isOneShot = oneShotShape != null;
    final docPos = _getDocPoint(event.localPosition);

    if (isOneShot) {
      _activePointerId = event.pointer;
      startTrackingPointer(event.pointer, event.transform);
      resolve(GestureDisposition.accepted);
      controller.startShape(docPos);
      return;
    }

    if (selectedShapeId != null && !isStylus) {
      final selectedShape = controller.shapes.cast<DrawnShape?>().firstWhere(
        (s) => s?.id == selectedShapeId,
        orElse: () => null,
      );
      if (selectedShape != null && paddedShapeBounds(selectedShape).contains(docPos)) {
        return;
      }
    }

    if (selectedStrokeId != null && !isStylus) {
      final selectedStroke = controller.strokes.cast<DrawingStroke?>().firstWhere(
        (s) => s?.id == selectedStrokeId,
        orElse: () => null,
      );
      if (selectedStroke != null && paddedStrokeBounds(selectedStroke).contains(docPos)) {
        return;
      }
    }

    if (!isStylus && activeTool == EditorTool.select) {
      return;
    }

    if (stylusOnly) {
      if (!isStylus) {
        return;
      }
    } else {
      if (!isDrawingMode && !isStylus) {
        return;
      }
    }

    _activePointerId = event.pointer;
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);

    final isEraser = _isEraserActive(event);

    if (isEraser) {
      controller.eraseAt(docPos);
    } else if (activeTool == EditorTool.shape) {
      controller.startShape(docPos);
    } else {
      if (activeTool != EditorTool.pen) {
        onStylusDrawStarted?.call();
      }
      controller.startStroke(docPos, event.pressure);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (_activePointerId != null && event.pointer != _activePointerId) {
      return;
    }

    final docPos = _getDocPoint(event.localPosition);
    final isEraser = _isEraserActive(event);
    final isOneShot = oneShotShape != null;

    if (event is PointerMoveEvent) {
      if (isEraser && !isOneShot) {
        if (controller.activeStrokePoints != null) {
          controller.cancelActiveStroke();
        }
        controller.eraseAt(docPos);
      } else if (isOneShot || activeTool == EditorTool.shape) {
        controller.updateShape(docPos);
      } else {
        controller.addStrokePoint(docPos, event.pressure);
      }
    } else if (event is PointerCancelEvent) {
      controller.cancelActiveStroke();
      controller.cancelActiveShape();
      _activePointerId = null;
      stopTrackingPointer(event.pointer);
    } else if (event is PointerUpEvent) {
      final page = currentPageGetter?.call() ?? currentPage;
      if (isEraser && !isOneShot) {
        controller.cancelActiveStroke();
      } else if (isOneShot) {
        controller.endShape(oneShotShape!, activeColor, activeStrokeWidth, page);
        onOneShotShapeCompleted?.call();
      } else if (activeTool == EditorTool.shape) {
        final distance = (controller.activeShapeEnd != null && controller.activeShapeStart != null)
            ? (controller.activeShapeEnd! - controller.activeShapeStart!).distance
            : 0.0;
        if (distance <= 5) {
          controller.startShape(docPos - const Offset(50, 30));
          controller.updateShape(docPos + const Offset(50, 30));
        }
        controller.endShape(activeShape, activeColor, activeStrokeWidth, page);
        onShapeCompleted?.call();
      } else {
        controller.endStroke(activeColor, activeStrokeWidth, page);
      }
      _activePointerId = null;
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  String get debugDescription => 'stylusDrawing';

  @override
  void didStopTrackingLastPointer(int pointer) {
    _activePointerId = null;
  }
}

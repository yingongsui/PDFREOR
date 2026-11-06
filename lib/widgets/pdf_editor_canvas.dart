import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../controllers/drawing_controller.dart';
import '../models/editor_models.dart';
import '../services/editor_settings_service.dart';
import 'pdf_canvas_items.dart';

export 'pdf_canvas_items.dart' show kEditableElementRegionGroup;

/// A Stack that does not reject hit-testing based on viewport size.
/// In document space (which can be multi-page, scrolled, and zoomed),
/// widgets placed anywhere in the document coordinates must receive hit testing.
class DocumentStack extends Stack {
  const DocumentStack({
    super.key,
    super.alignment = AlignmentDirectional.topStart,
    super.textDirection,
    super.fit = StackFit.loose,
    super.clipBehavior = Clip.none,
    super.children = const <Widget>[],
  });

  @override
  RenderDocumentStack createRenderObject(BuildContext context) {
    return RenderDocumentStack(
      alignment: alignment,
      textDirection: textDirection ?? Directionality.maybeOf(context),
      fit: fit,
      clipBehavior: clipBehavior,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderDocumentStack renderObject) {
    renderObject
      ..alignment = alignment
      ..textDirection = textDirection ?? Directionality.maybeOf(context)
      ..fit = fit
      ..clipBehavior = clipBehavior;
  }
}

class RenderDocumentStack extends RenderStack {
  RenderDocumentStack({
    super.alignment,
    super.textDirection,
    super.fit = StackFit.loose,
    super.clipBehavior = Clip.none,
  });

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hitTestChildren(result, position: position) || hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
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
  String? selectedShapeId;

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
    this.selectedShapeId,
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
    String? selectedShapeId,
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
    this.selectedShapeId = selectedShapeId;
  }

  bool _isStylus(PointerEvent event) {
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      return true;
    }
    if (event.kind == PointerDeviceKind.unknown) {
      return true;
    }
    if (event.kind == PointerDeviceKind.touch) {
      if (event.pressure > 0.0 && event.pressure != 1.0) {
        return true;
      }
    }
    return false;
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
    final isStylus = _isStylus(event);
    if (isStylus) {
      onStylusDetected?.call();
    }

    final isOneShot = oneShotShape != null;
    final docPos = _getDocPoint(event.localPosition);

    if (isOneShot) {
      startTrackingPointer(event.pointer, event.transform);
      resolve(GestureDisposition.accepted);
      controller.startShape(docPos);
      return;
    }

    if (selectedShapeId != null) {
      final selectedShape = controller.shapes.cast<DrawnShape?>().firstWhere(
        (s) => s?.id == selectedShapeId,
        orElse: () => null,
      );
      if (selectedShape != null) {
        final minX = math.min(selectedShape.start.dx, selectedShape.end.dx) - 48.0;
        final maxX = math.max(selectedShape.start.dx, selectedShape.end.dx) + 48.0;
        final minY = math.min(selectedShape.start.dy, selectedShape.end.dy) - 48.0;
        final maxY = math.max(selectedShape.start.dy, selectedShape.end.dy) + 48.0;
        final bounds = Rect.fromLTRB(minX, minY, maxX, maxY);
        if (bounds.contains(docPos)) {
          if (!isStylus) {
            return;
          }
        }
      }
    }

    if (isStylus) {
      onStylusDetected?.call();
    } else {
      if (activeTool == EditorTool.select) {
        return;
      }
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
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      final page = currentPageGetter?.call() ?? currentPage;
      if (isEraser && !isOneShot) {
        controller.cancelActiveStroke();
      } else if (isOneShot) {
        controller.endShape(oneShotShape!, activeColor, activeStrokeWidth, page);
        onOneShotShapeCompleted?.call();
      } else if (activeTool == EditorTool.shape) {
        controller.endShape(activeShape, activeColor, activeStrokeWidth, page);
      } else {
        controller.endStroke(activeColor, activeStrokeWidth, page);
      }
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  String get debugDescription => 'stylusDrawing';

  @override
  void didStopTrackingLastPointer(int pointer) {}
}

IconData _getShapeIcon(ShapeType type) {
  switch (type) {
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

String _getShapeName(ShapeType type) {
  switch (type) {
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

class PdfEditorCanvas extends StatefulWidget {
  final DrawingController controller;
  final TransformationController? transformationController;
  final EditorTool activeTool;
  final ShapeType activeShape;
  final Color activeColor;
  final double activeStrokeWidth;
  final int currentPage;
  final int Function()? currentPageGetter;
  final bool stylusOnlyMode;
  final bool isStylusDetected;
  final bool isHardwareButtonPressed;
  final ShapeType? oneShotShape;
  final VoidCallback? onOneShotShapeCompleted;
  final VoidCallback? onCancelOneShotShape;
  final bool hasActiveTextSelection;
  final void Function(Offset screenPos, Offset docPos)? onNonTextLongPressed;
  final String? editingTextBoxId;
  final ValueChanged<String?>? onEditingTextBoxChanged;
  final String? selectedShapeId;
  final ValueChanged<String?>? onSelectedShapeChanged;
  final String? selectedStrokeId;
  final ValueChanged<String?>? onSelectedStrokeChanged;
  final String? selectedTextAnnotationId;
  final ValueChanged<String?>? onSelectedTextAnnotationChanged;
  final ValueChanged<bool>? onPointerEraserStateChanged;
  final ValueChanged<Offset> onAddTextBoxRequested;
  final VoidCallback? onStylusDetected;
  final VoidCallback? onStylusDrawStarted;
  final AppFontFamily textBoxFont;

  const PdfEditorCanvas({
    super.key,
    required this.controller,
    this.transformationController,
    required this.activeTool,
    required this.activeShape,
    required this.activeColor,
    required this.activeStrokeWidth,
    required this.currentPage,
    this.currentPageGetter,
    required this.stylusOnlyMode,
    this.isStylusDetected = false,
    this.isHardwareButtonPressed = false,
    this.oneShotShape,
    this.onOneShotShapeCompleted,
    this.onCancelOneShotShape,
    this.hasActiveTextSelection = false,
    this.onNonTextLongPressed,
    this.editingTextBoxId,
    this.onEditingTextBoxChanged,
    this.selectedShapeId,
    this.onSelectedShapeChanged,
    this.selectedStrokeId,
    this.onSelectedStrokeChanged,
    this.selectedTextAnnotationId,
    this.onSelectedTextAnnotationChanged,
    this.onPointerEraserStateChanged,
    required this.onAddTextBoxRequested,
    this.onStylusDetected,
    this.onStylusDrawStarted,
    this.textBoxFont = AppFontFamily.sansSerif,
  });

  @override
  State<PdfEditorCanvas> createState() => _PdfEditorCanvasState();
}

class _PdfEditorCanvasState extends State<PdfEditorCanvas> {
  Timer? _longPressTimer;
  Offset? _pointerDownScreenPos;
  int? _pointerDownId;
  late Listenable _savedPaintListenable;
  late Listenable _activePaintListenable;

  @override
  void initState() {
    super.initState();
    _rebuildPaintListenables();
  }

  void _rebuildPaintListenables() {
    final tc = widget.transformationController;
    _savedPaintListenable = tc != null
        ? Listenable.merge([widget.controller.savedLayerListenable, tc])
        : widget.controller.savedLayerListenable;
    _activePaintListenable = tc != null
        ? Listenable.merge([widget.controller.activeLayerListenable, tc])
        : widget.controller.activeLayerListenable;
  }

  String? get _selectedShapeId => widget.selectedShapeId;
  String? get _selectedStrokeId => widget.selectedStrokeId;
  String? get _selectedTextAnnotationId => widget.selectedTextAnnotationId;

  void _setSelectedShape(String? id) {
    widget.onSelectedShapeChanged?.call(id);
  }

  void _setSelectedStroke(String? id) {
    widget.onSelectedStrokeChanged?.call(id);
  }

  void _setSelectedTextAnnotation(String? id) {
    widget.onSelectedTextAnnotationChanged?.call(id);
  }

  bool get _isDrawingMode =>
      widget.activeTool == EditorTool.pen ||
      widget.activeTool == EditorTool.shape ||
      widget.activeTool == EditorTool.eraser ||
      widget.activeTool == EditorTool.textBox;

  void _checkPointer(PointerEvent event) {
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      widget.onStylusDetected?.call();
    }
    final isPressed = (event.buttons &
            (kPrimaryStylusButton | kSecondaryStylusButton | kSecondaryMouseButton)) !=
        0;
    widget.onPointerEraserStateChanged?.call(isPressed);
  }

  void _handlePointerDown(PointerDownEvent event) {
    _checkPointer(event);

    final docPos = widget.transformationController?.toScene(event.localPosition) ??
        event.localPosition;

    final isEraser = widget.isHardwareButtonPressed ||
        widget.activeTool == EditorTool.eraser ||
        (event.buttons &
            (kPrimaryStylusButton | kSecondaryStylusButton | kSecondaryMouseButton)) != 0;

    final isStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;

    final isFingerTouchMode = !isStylus &&
        (widget.isStylusDetected || widget.stylusOnlyMode || widget.activeTool == EditorTool.select);
    final canSelectElements = isFingerTouchMode || (!isStylus && widget.activeTool == EditorTool.select);

    if (canSelectElements &&
        (event.buttons & kSecondaryMouseButton) == 0 &&
        widget.oneShotShape == null &&
        !widget.hasActiveTextSelection &&
        !isEraser) {
      if (_selectedShapeId != null) {
        final selectedShape = widget.controller.shapes.cast<DrawnShape?>().firstWhere(
          (s) => s?.id == _selectedShapeId,
          orElse: () => null,
        );
        if (selectedShape != null) {
          final minX = math.min(selectedShape.start.dx, selectedShape.end.dx) - 48.0;
          final maxX = math.max(selectedShape.start.dx, selectedShape.end.dx) + 48.0;
          final minY = math.min(selectedShape.start.dy, selectedShape.end.dy) - 48.0;
          final maxY = math.max(selectedShape.start.dy, selectedShape.end.dy) + 48.0;
          final bounds = Rect.fromLTRB(minX, minY, maxX, maxY);
          if (!bounds.contains(docPos)) {
            final otherShape = widget.controller.hitTestShape(docPos, 24.0);
            _setSelectedShape(otherShape?.id);
            if (otherShape != null) {
              _setSelectedStroke(null);
              _longPressTimer?.cancel();
              _pointerDownScreenPos = null;
              return;
            }
          } else {
            _longPressTimer?.cancel();
            _pointerDownScreenPos = null;
            return;
          }
        }
      }

      final hitShape = widget.controller.hitTestShape(docPos, 24.0);
      if (hitShape != null) {
        _setSelectedShape(hitShape.id);
        _setSelectedStroke(null);
        _longPressTimer?.cancel();
        _pointerDownScreenPos = null;
        return;
      }

      final hitStroke = widget.controller.hitTestStroke(docPos, 20.0);
      if (hitStroke != null) {
        _setSelectedStroke(hitStroke.id);
        _setSelectedShape(null);
        _setSelectedTextAnnotation(null);
        _longPressTimer?.cancel();
        _pointerDownScreenPos = null;
        return;
      }

      final hitTa = widget.controller.hitTestTextAnnotation(docPos, 6.0);
      if (hitTa != null) {
        _setSelectedTextAnnotation(hitTa.id);
        _setSelectedShape(null);
        _setSelectedStroke(null);
        _longPressTimer?.cancel();
        _pointerDownScreenPos = null;
        return;
      }

      if (_selectedShapeId != null) {
        _setSelectedShape(null);
      }
      if (_selectedStrokeId != null) {
        _setSelectedStroke(null);
      }
      if (_selectedTextAnnotationId != null) {
        _setSelectedTextAnnotation(null);
      }
    } else if (!canSelectElements) {
      if (isStylus || widget.activeTool == EditorTool.shape) {
        if (_selectedShapeId != null) {
          _setSelectedShape(null);
        }
        if (_selectedStrokeId != null) {
          _setSelectedStroke(null);
        }
        if (_selectedTextAnnotationId != null) {
          _setSelectedTextAnnotation(null);
        }
      }
    }

    if (event.kind == PointerDeviceKind.mouse && (event.buttons & kSecondaryMouseButton) != 0) {
      if (!widget.hasActiveTextSelection) {
        widget.onNonTextLongPressed?.call(event.position, docPos);
      }
      return;
    }

    if (widget.oneShotShape != null) return;
    if (widget.hasActiveTextSelection) return;

    if (isStylus || isEraser || widget.onNonTextLongPressed == null) {
      _longPressTimer?.cancel();
      _pointerDownScreenPos = null;
      return;
    }

    _pointerDownScreenPos = event.position;
    _pointerDownId = event.pointer;
    _longPressTimer?.cancel();

    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      if (_pointerDownScreenPos != null && !widget.hasActiveTextSelection) {
        widget.onNonTextLongPressed?.call(_pointerDownScreenPos!, docPos);
      }
      _pointerDownScreenPos = null;
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pointerDownScreenPos != null && event.pointer == _pointerDownId) {
      if ((event.position - _pointerDownScreenPos!).distance > kTouchSlop) {
        _longPressTimer?.cancel();
        _pointerDownScreenPos = null;
      }
    }
    if (event.kind == PointerDeviceKind.touch) {
      return;
    }
    _checkPointer(event);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      _checkPointer(event);
    }
    if (event.pointer == _pointerDownId) {
      _longPressTimer?.cancel();
      _pointerDownScreenPos = null;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      _checkPointer(event);
    }
    _longPressTimer?.cancel();
    _pointerDownScreenPos = null;
  }

  @override
  void didUpdateWidget(covariant PdfEditorCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller ||
        widget.transformationController != oldWidget.transformationController) {
      _rebuildPaintListenables();
    }
    if (widget.hasActiveTextSelection) {
      _longPressTimer?.cancel();
      _pointerDownScreenPos = null;
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasWidgetAnnotations = widget.controller.shapes.isNotEmpty ||
        widget.controller.images.isNotEmpty ||
        widget.controller.textBoxes.isNotEmpty;

    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        // 1a. Committed strokes & text annotations rendered in viewport space with frustum culling
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              isComplex: true,
              painter: _SavedAnnotationsPainter(
                repaint: _savedPaintListenable,
                controller: widget.controller,
                transformationController: widget.transformationController,
                selectedStrokeId: _selectedStrokeId,
                selectedTextAnnotationId: _selectedTextAnnotationId,
              ),
            ),
          ),
        ),
        // 1b. Active in-progress stroke / shape preview layer (isolated 240Hz RepaintBoundary)
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _ActiveAnnotationPainter(
                  repaint: _activePaintListenable,
                  controller: widget.controller,
                  transformationController: widget.transformationController,
                  currentColor: widget.activeColor,
                  currentStrokeWidth: widget.activeStrokeWidth,
                  shapeType: widget.oneShotShape ?? widget.activeShape,
                ),
              ),
            ),
          ),
        ),
        // 2-4. Interactive widget annotations (mounted only when present to avoid scroll rebuilds)
        if (hasWidgetAnnotations)
          AnimatedBuilder(
            animation: widget.transformationController ?? const AlwaysStoppedAnimation(null),
            builder: (context, child) {
              final matrix = widget.transformationController?.value ?? Matrix4.identity();
              return Transform(
                transform: matrix,
                alignment: Alignment.topLeft,
                child: child,
              );
            },
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: DocumentStack(
                clipBehavior: Clip.none,
                children: [
                  for (final shape in widget.controller.shapes)
                    _buildShapeWidget(shape),
                  for (final img in widget.controller.images)
                    ImageCanvasItem(
                      key: ValueKey('img_${img.id}'),
                      image: img,
                      transformationController: widget.transformationController,
                      onUpdate: (newPos, newW, newH) {
                        img.position = newPos;
                        img.width = newW;
                        img.height = newH;
                        widget.controller.updateImage(img);
                      },
                      onModificationCommitted: (oldPos, oldW, oldH) {
                        widget.controller.recordImageModification(img, oldPos, oldW, oldH);
                      },
                      onDelete: () => widget.controller.deleteImage(img.id),
                    ),
                  for (final tb in widget.controller.textBoxes)
                    Positioned(
                      key: ValueKey(tb.id),
                      left: tb.position.dx,
                      top: tb.position.dy,
                      child: TextBoxCanvasItem(
                        key: ValueKey('tb_${tb.id}'),
                        textBox: tb,
                        textBoxFont: widget.textBoxFont,
                        transformationController: widget.transformationController,
                        isEditing: widget.editingTextBoxId == tb.id,
                        onStartEditing: () => widget.onEditingTextBoxChanged?.call(tb.id),
                        onFinishEditing: () => widget.onEditingTextBoxChanged?.call(null),
                        onUpdate: (newText, newPos, newFontSize, newWidth) {
                          tb.text = newText;
                          tb.position = newPos;
                          tb.fontSize = newFontSize;
                          tb.width = newWidth;
                          widget.controller.updateTextBox(tb);
                        },
                        onLayoutModificationCommitted: (oldPos, oldWidth) {
                          widget.controller.recordTextBoxLayoutModification(tb, oldPos, oldWidth);
                        },
                        onDelete: () {
                          if (widget.editingTextBoxId == tb.id) {
                            widget.onEditingTextBoxChanged?.call(null);
                          }
                          widget.controller.deleteTextBox(tb.id);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        // Top banner for one-shot shape drawing
        if (widget.oneShotShape != null)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(20),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getShapeIcon(widget.oneShotShape!),
                        size: 18,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Drag with finger to draw ${_getShapeName(widget.oneShotShape!)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: widget.onCancelOneShotShape,
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (widget.activeTool == EditorTool.textBox && widget.oneShotShape == null) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (details) {
          final docPos = widget.transformationController?.toScene(details.localPosition) ??
              details.localPosition;
          widget.onAddTextBoxRequested(docPos);
        },
        child: content,
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: _checkPointer,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          StylusDrawingGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<StylusDrawingGestureRecognizer>(
            () => StylusDrawingGestureRecognizer(
              stylusOnly: widget.stylusOnlyMode,
              isDrawingMode: _isDrawingMode,
              activeTool: widget.activeTool,
              activeShape: widget.activeShape,
              activeColor: widget.activeColor,
              activeStrokeWidth: widget.activeStrokeWidth,
              currentPage: widget.currentPage,
              currentPageGetter: widget.currentPageGetter,
              controller: widget.controller,
              transformationController: widget.transformationController,
              isHardwareButtonPressed: widget.isHardwareButtonPressed,
              oneShotShape: widget.oneShotShape,
              onOneShotShapeCompleted: widget.onOneShotShapeCompleted,
              onStylusDetected: widget.onStylusDetected,
              onStylusDrawStarted: widget.onStylusDrawStarted,
              selectedShapeId: _selectedShapeId,
            ),
            (instance) {
              instance.update(
                stylusOnly: widget.stylusOnlyMode,
                isDrawingMode: _isDrawingMode,
                activeTool: widget.activeTool,
                activeShape: widget.activeShape,
                activeColor: widget.activeColor,
                activeStrokeWidth: widget.activeStrokeWidth,
                currentPage: widget.currentPage,
                currentPageGetter: widget.currentPageGetter,
                controller: widget.controller,
                transformationController: widget.transformationController,
                isHardwareButtonPressed: widget.isHardwareButtonPressed,
                oneShotShape: widget.oneShotShape,
                onOneShotShapeCompleted: widget.onOneShotShapeCompleted,
                onStylusDetected: widget.onStylusDetected,
                onStylusDrawStarted: widget.onStylusDrawStarted,
                selectedShapeId: _selectedShapeId,
              );
            },
          ),
        },
        child: content,
      ),
    );
  }

  Widget _buildShapeWidget(DrawnShape shape) {
    final minX = math.min(shape.start.dx, shape.end.dx);
    final maxX = math.max(shape.start.dx, shape.end.dx);
    final minY = math.min(shape.start.dy, shape.end.dy);
    final maxY = math.max(shape.start.dy, shape.end.dy);
    final width = maxX - minX;
    final height = maxY - minY;
    const kPadding = 48.0;

    return Positioned(
      key: ValueKey('shape_${shape.id}'),
      left: minX - kPadding,
      top: minY - kPadding,
      width: width + kPadding * 2,
      height: height + kPadding * 2,
      child: ShapeCanvasItem(
        key: ValueKey('sw_${shape.id}'),
        shape: shape,
        isSelected: _selectedShapeId == shape.id,
        transformationController: widget.transformationController,
        onSelect: () => _setSelectedShape(shape.id),
        onDeselect: () {
          if (_selectedShapeId == shape.id) {
            _setSelectedShape(null);
          }
        },
        onUpdate: (newStart, newEnd) {
          shape.start = newStart;
          shape.end = newEnd;
          widget.controller.updateDrawnShape(shape);
        },
        onModificationCommitted: (oldStart, oldEnd) {
          widget.controller.recordShapeModification(shape, oldStart, oldEnd);
        },
        onDelete: () {
          if (_selectedShapeId == shape.id) {
            _setSelectedShape(null);
          }
          widget.controller.deleteDrawnShape(shape.id);
        },
      ),
    );
  }
}

void _paintStrokePoints(Canvas canvas, List<StrokePoint> points, Color color, double baseWidth) {
  if (points.isEmpty) return;
  if (points.length == 1) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(points.first.offset, baseWidth / 2, paint);
    return;
  }

  final paint = Paint()
    ..color = color
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  for (int i = 0; i < points.length - 1; i++) {
    final p1 = points[i];
    final p2 = points[i + 1];
    final avgPressure = (p1.pressure + p2.pressure) / 2;
    final pressureScale = (avgPressure > 0.0 && avgPressure != 1.0)
        ? (0.75 + 0.5 * avgPressure.clamp(0.0, 1.0))
        : 1.0;
    paint.strokeWidth = math.max(0.5, baseWidth * pressureScale);
    canvas.drawLine(p1.offset, p2.offset, paint);
  }
}

class _SavedAnnotationsPainter extends CustomPainter {
  final DrawingController controller;
  final TransformationController? transformationController;
  final String? selectedStrokeId;
  final String? selectedTextAnnotationId;

  _SavedAnnotationsPainter({
    required super.repaint,
    required this.controller,
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

    for (final ta in controller.textAnnotations) {
      final isSelected = ta.id == selectedTextAnnotationId;
      if (!isSelected && !ta.getBounds().overlaps(visibleDocRect)) {
        continue;
      }
      switch (ta.type) {
        case TextAnnotationType.highlight:
          final paint = Paint()
            ..color = ta.color.withValues(alpha: 0.38)
            ..style = PaintingStyle.fill
            ..blendMode = BlendMode.multiply;
          for (final rect in ta.rects) {
            canvas.drawRect(rect, paint);
          }
          if (isSelected) {
            final selPaint = Paint()
              ..color = const Color(0xFF1E88E5)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5;
            for (final rect in ta.rects) {
              canvas.drawRect(rect.inflate(1.5), selPaint);
            }
          }
          break;
        case TextAnnotationType.underline:
          final paint = Paint()
            ..color = ta.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;
          for (final rect in ta.rects) {
            canvas.drawLine(rect.bottomLeft, rect.bottomRight, paint);
          }
          if (isSelected) {
            final selPaint = Paint()
              ..color = const Color(0xFF1E88E5)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0;
            for (final rect in ta.rects) {
              canvas.drawRect(rect.inflate(2.0), selPaint);
            }
          }
          break;
        case TextAnnotationType.strikethrough:
          final paint = Paint()
            ..color = ta.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8;
          for (final rect in ta.rects) {
            final midY = (rect.top + rect.bottom) / 2;
            canvas.drawLine(Offset(rect.left, midY), Offset(rect.right, midY), paint);
          }
          if (isSelected) {
            final selPaint = Paint()
              ..color = const Color(0xFF1E88E5)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0;
            for (final rect in ta.rects) {
              canvas.drawRect(rect.inflate(2.0), selPaint);
            }
          }
          break;
      }
    }

    for (final stroke in controller.strokes) {
      final isSelected = stroke.id == selectedStrokeId;
      final pad = stroke.strokeWidth + 12.0;
      if (!isSelected && !stroke.getBounds().inflate(pad).overlaps(visibleDocRect)) {
        continue;
      }
      if (isSelected) {
        final glowPaint = Paint()
          ..color = const Color(0xFF1E88E5).withValues(alpha: 0.38)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.strokeWidth + 10.0;
        for (int i = 0; i < stroke.points.length - 1; i++) {
          canvas.drawLine(stroke.points[i].offset, stroke.points[i + 1].offset, glowPaint);
        }
        final bounds = stroke.getBounds().inflate(6.0 + stroke.strokeWidth / 2);
        final boxPaint = Paint()
          ..color = const Color(0xFF1E88E5).withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawRRect(RRect.fromRectAndRadius(bounds, const Radius.circular(8)), boxPaint);
      }
      _paintStrokePoints(canvas, stroke.points, stroke.color, stroke.strokeWidth);
    }

    if (tc != null) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SavedAnnotationsPainter oldDelegate) {
    return oldDelegate.selectedStrokeId != selectedStrokeId ||
        oldDelegate.selectedTextAnnotationId != selectedTextAnnotationId ||
        oldDelegate.transformationController != transformationController ||
        oldDelegate.controller != controller;
  }
}

class _ActiveAnnotationPainter extends CustomPainter {
  final DrawingController controller;
  final TransformationController? transformationController;
  final Color currentColor;
  final double currentStrokeWidth;
  final ShapeType shapeType;

  _ActiveAnnotationPainter({
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
      _paintStrokePoints(
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
        final arrowLength = math.max(strokeWidth * 4.0, 12.0);
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

  @override
  bool shouldRepaint(covariant _ActiveAnnotationPainter oldDelegate) {
    return oldDelegate.currentColor != currentColor ||
        oldDelegate.currentStrokeWidth != currentStrokeWidth ||
        oldDelegate.shapeType != shapeType ||
        oldDelegate.transformationController != transformationController ||
        oldDelegate.controller != controller;
  }
}

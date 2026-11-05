import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../controllers/drawing_controller.dart';
import '../models/editor_models.dart';
import '../services/editor_settings_service.dart';

/// TapRegion group id shared by editable elements and the bottom property bar
const String kEditableElementRegionGroup = 'EditableElementRegionGroup';

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
    // Also consider pressure-sensitive hardware digitizer
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

    // 1. One-shot shape drawing (from long-press menu):
    // MUST work immediately with finger or stylus, winning the gesture arena!
    if (isOneShot) {
      startTrackingPointer(event.pointer, event.transform);
      resolve(GestureDisposition.accepted);
      controller.startShape(docPos);
      return;
    }

    // If a shape is currently selected, do not capture if pointer is on or near it
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
        // Palm rejection active: fingers are rejected by the drawing recognizer
        // so that the underlying SfPdfViewer handles scrolling, pinch-zoom, and text selection.
        return;
      }
    } else {
      // Palm rejection inactive:
      if (!isDrawingMode && !isStylus) {
        return;
      }
    }

    // Stylus touches (or finger touches when in drawing mode) win the gesture arena immediately.
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);

    final isEraser = _isEraserActive(event);

    if (isEraser) {
      controller.eraseAt(docPos);
    } else if (activeTool == EditorTool.shape) {
      controller.startShape(docPos);
    } else {
      // Default to pen drawing
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
      if (isEraser && !isOneShot) {
        controller.cancelActiveStroke();
      } else if (isOneShot) {
        controller.endShape(oneShotShape!, activeColor, activeStrokeWidth, currentPage);
        onOneShotShapeCompleted?.call();
      } else if (activeTool == EditorTool.shape) {
        controller.endShape(activeShape, activeColor, activeStrokeWidth, currentPage);
      } else {
        controller.endStroke(activeColor, activeStrokeWidth, currentPage);
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

    // Stylus is dedicated to writing/erasing; finger in touch/dual mode selects and adjusts shapes/strokes.
    final isFingerTouchMode = !isStylus &&
        (widget.isStylusDetected || widget.stylusOnlyMode || widget.activeTool == EditorTool.select);
    final canSelectElements = isFingerTouchMode || (!isStylus && widget.activeTool == EditorTool.select);

    if (canSelectElements &&
        (event.buttons & kSecondaryMouseButton) == 0 &&
        widget.oneShotShape == null &&
        !widget.hasActiveTextSelection &&
        !isEraser) {
      // 1. If currently a shape is selected:
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
            // Tapped outside selected shape: check if another shape was tapped
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

      // 2. Check if clicking on or near any shape
      final hitShape = widget.controller.hitTestShape(docPos, 24.0);
      if (hitShape != null) {
        _setSelectedShape(hitShape.id);
        _setSelectedStroke(null);
        _longPressTimer?.cancel();
        _pointerDownScreenPos = null;
        return;
      }

      // 3. Check if clicking on or near any pen stroke
      final hitStroke = widget.controller.hitTestStroke(docPos, 20.0);
      if (hitStroke != null) {
        _setSelectedStroke(hitStroke.id);
        _setSelectedShape(null);
        _setSelectedTextAnnotation(null);
        _longPressTimer?.cancel();
        _pointerDownScreenPos = null;
        return;
      }

      // 4. Check if clicking on any text annotation (highlight, underline, strikethrough)
      final hitTa = widget.controller.hitTestTextAnnotation(docPos, 6.0);
      if (hitTa != null) {
        _setSelectedTextAnnotation(hitTa.id);
        _setSelectedShape(null);
        _setSelectedStroke(null);
        _longPressTimer?.cancel();
        _pointerDownScreenPos = null;
        return;
      }

      // Tapped empty area: deselect shape, stroke, and text annotation
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
      // In pen / shape / eraser mode, ensure any previously selected stroke, shape, or text annotation is deselected
      // when stylus draws or user switches to shape creation mode.
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

    // 2. Secondary button / mouse right click triggers context menu immediately ONLY for mouse!
    if (event.kind == PointerDeviceKind.mouse && (event.buttons & kSecondaryMouseButton) != 0) {
      if (!widget.hasActiveTextSelection) {
        widget.onNonTextLongPressed?.call(event.position, docPos);
      }
      return;
    }

    if (widget.oneShotShape != null) return;
    if (widget.hasActiveTextSelection) return;

    // NEVER trigger finger long-press menu from any stylus input or when eraser/button is active!
    if (isStylus || isEraser) {
      _longPressTimer?.cancel();
      _pointerDownScreenPos = null;
      return;
    }

    _pointerDownScreenPos = event.position;
    _pointerDownId = event.pointer;
    _longPressTimer?.cancel();

    _longPressTimer = Timer(const Duration(milliseconds: 700), () {
      if (_pointerDownScreenPos != null && !widget.hasActiveTextSelection) {
        widget.onNonTextLongPressed?.call(_pointerDownScreenPos!, docPos);
      }
      _pointerDownScreenPos = null;
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pointerDownScreenPos != null && event.pointer == _pointerDownId) {
      if ((event.position - _pointerDownScreenPos!).distance > 12.0) {
        _longPressTimer?.cancel();
        _pointerDownScreenPos = null;
      }
    } else if (widget.activeTool == EditorTool.select && _selectedShapeId == null) {
      // In select mode while scrolling, skip all pointer move computations
      return;
    }
    _checkPointer(event);
  }

  void _handlePointerUp(PointerUpEvent event) {
    _checkPointer(event);
    if (event.pointer == _pointerDownId) {
      _longPressTimer?.cancel();
      _pointerDownScreenPos = null;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _checkPointer(event);
    _longPressTimer?.cancel();
    _pointerDownScreenPos = null;
  }

  @override
  void didUpdateWidget(covariant PdfEditorCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    final hasAnnotations = widget.controller.strokes.isNotEmpty ||
        widget.controller.shapes.isNotEmpty ||
        widget.controller.images.isNotEmpty ||
        widget.controller.textBoxes.isNotEmpty ||
        widget.controller.textAnnotations.isNotEmpty ||
        widget.controller.activeStrokePoints != null ||
        widget.controller.activeShapeStart != null ||
        _selectedStrokeId != null ||
        _selectedTextAnnotationId != null;

    if (!hasAnnotations &&
        widget.activeTool == EditorTool.select &&
        widget.oneShotShape == null) {
      // In select/reading mode with zero annotations, completely bypass all canvas gesture
      // interceptors, timers, and Transform animations so 100% of touches go directly to SfPdfViewer at 120Hz/144Hz!
      return const SizedBox.shrink();
    }

    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        // All vector annotations (strokes, shapes, images, textboxes) transformed seamlessly on GPU
        if (hasAnnotations)
          AnimatedBuilder(
            animation: widget.transformationController ?? ValueNotifier(null),
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
                  // 1. Strokes Layer in document space
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        isComplex: true,
                        painter: _EditorPainter(
                          repaint: widget.controller,
                          controller: widget.controller,
                          currentColor: widget.activeColor,
                          currentStrokeWidth: widget.activeStrokeWidth,
                          shapeType: widget.oneShotShape ?? widget.activeShape,
                          selectedStrokeId: _selectedStrokeId,
                          selectedTextAnnotationId: _selectedTextAnnotationId,
                        ),
                      ),
                    ),
                  ),
                  // 2. Shapes
                  for (final shape in widget.controller.shapes)
                    _buildShapeWidget(shape),
                  // 3. Pasted Images
                  for (final img in widget.controller.images)
                    _ImageWidget(
                      image: img,
                      onUpdate: (newPos, newW, newH) {
                        img.position = newPos;
                        img.width = newW;
                        img.height = newH;
                        widget.controller.updateImage(img);
                      },
                      onDelete: () => widget.controller.deleteImage(img.id),
                    ),
                  // 4. Text Boxes
                  for (final tb in widget.controller.textBoxes)
                    Positioned(
                      key: ValueKey(tb.id),
                      left: tb.position.dx,
                      top: tb.position.dy,
                      child: _TextBoxWidget(
                        key: ValueKey('tb_${tb.id}'),
                        textBox: tb,
                        textBoxFont: widget.textBoxFont,
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
          final docPos = widget.transformationController?.toScene(details.localPosition) ?? details.localPosition;
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
      child: _ShapeWidget(
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

class _EditorPainter extends CustomPainter {
  final DrawingController controller;
  final Color currentColor;
  final double currentStrokeWidth;
  final ShapeType shapeType;
  final String? selectedStrokeId;
  final String? selectedTextAnnotationId;

  _EditorPainter({
    required super.repaint,
    required this.controller,
    required this.currentColor,
    required this.currentStrokeWidth,
    required this.shapeType,
    this.selectedStrokeId,
    this.selectedTextAnnotationId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 0. Draw text annotations (highlights, underlines, strikethroughs)
    for (final ta in controller.textAnnotations) {
      final isSelected = ta.id == selectedTextAnnotationId;
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

    // 1. Draw saved strokes in document space
    for (final stroke in controller.strokes) {
      if (stroke.id == selectedStrokeId) {
        // Draw selection halo around selected stroke
        final glowPaint = Paint()
          ..color = const Color(0xFF1E88E5).withValues(alpha: 0.38)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.strokeWidth + 10.0;
        for (int i = 0; i < stroke.points.length - 1; i++) {
          canvas.drawLine(stroke.points[i].offset, stroke.points[i + 1].offset, glowPaint);
        }
        // Draw subtle selection bounding box
        final bounds = stroke.getBounds().inflate(6.0 + stroke.strokeWidth / 2);
        final boxPaint = Paint()
          ..color = const Color(0xFF1E88E5).withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawRRect(RRect.fromRectAndRadius(bounds, const Radius.circular(8)), boxPaint);
      }
      _drawStroke(canvas, stroke.points, stroke.color, stroke.strokeWidth);
    }

    // 2. Draw currently active stroke in document space
    if (controller.activeStrokePoints != null && controller.activeStrokePoints!.isNotEmpty) {
      _drawStroke(canvas, controller.activeStrokePoints!, currentColor, currentStrokeWidth);
    }

    // 3. Draw currently active shape preview
    if (controller.activeShapeStart != null && controller.activeShapeEnd != null) {
      _drawShape(
        canvas,
        shapeType,
        controller.activeShapeStart!,
        controller.activeShapeEnd!,
        currentColor,
        currentStrokeWidth,
      );
    }
  }

  void _drawStroke(Canvas canvas, List<StrokePoint> points, Color color, double baseWidth) {
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
      // Modulate stroke width smoothly around baseWidth based on stylus pressure.
      // Active stylus pressure typically ranges between 0.05 and 0.5.
      // Scaling moderately around baseWidth ensures the toolbar stroke width setting
      // directly determines the line thickness, while stylus pressure adds natural organic dynamics.
      final pressureScale = (avgPressure > 0.0 && avgPressure != 1.0)
          ? (0.75 + 0.5 * avgPressure.clamp(0.0, 1.0))
          : 1.0;
      paint.strokeWidth = math.max(0.5, baseWidth * pressureScale);
      canvas.drawLine(p1.offset, p2.offset, paint);
    }
  }

  void _drawShape(
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
  bool shouldRepaint(covariant _EditorPainter oldDelegate) => true;
}

class _ShapeHandle extends StatelessWidget {
  final Offset position;
  final double touchSize;
  final double visualSize;
  final double borderWidth;
  final void Function(DragStartDetails details)? onPanStart;
  final void Function(DragUpdateDetails details) onPanUpdate;
  final VoidCallback? onPanEnd;

  const _ShapeHandle({
    required this.position,
    required this.touchSize,
    required this.visualSize,
    required this.borderWidth,
    this.onPanStart,
    required this.onPanUpdate,
    this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - touchSize / 2,
      top: position.dy - touchSize / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: (_) => onPanEnd?.call(),
        child: Container(
          width: touchSize,
          height: touchSize,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: Container(
            width: visualSize,
            height: visualSize,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF1976D2),
                width: math.max(1.5, borderWidth),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 3.0,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SingleShapePainter extends CustomPainter {
  final DrawnShape shape;
  final bool isSelected;
  final double kPadding;
  final double scale;

  _SingleShapePainter({
    required this.shape,
    required this.isSelected,
    required this.kPadding,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final minX = math.min(shape.start.dx, shape.end.dx);
    final maxX = math.max(shape.start.dx, shape.end.dx);
    final minY = math.min(shape.start.dy, shape.end.dy);
    final maxY = math.max(shape.start.dy, shape.end.dy);
    final width = maxX - minX;
    final height = maxY - minY;

    final localStart = Offset(
      shape.start.dx - minX + kPadding,
      shape.start.dy - minY + kPadding,
    );
    final localEnd = Offset(
      shape.end.dx - minX + kPadding,
      shape.end.dy - minY + kPadding,
    );

    final shapeRect = Rect.fromLTWH(kPadding, kPadding, width, height);

    // 1. Draw selection highlight bounding box if selected
    if (isSelected) {
      final highlightPaint = Paint()
        ..color = const Color(0xFF2196F3).withValues(alpha: 0.5)
        ..strokeWidth = math.max(1.0, 1.5 / scale)
        ..style = PaintingStyle.stroke;

      final bounds = shapeRect.inflate(4.0 / scale);
      canvas.drawRect(bounds, highlightPaint);
    }

    // 2. Draw the shape itself
    final paint = Paint()
      ..color = shape.color
      ..strokeWidth = shape.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (shape.type) {
      case ShapeType.rectangle:
        canvas.drawRect(shapeRect, paint);
        break;

      case ShapeType.circle:
        canvas.drawOval(shapeRect, paint);
        break;

      case ShapeType.line:
        canvas.drawLine(localStart, localEnd, paint);
        break;

      case ShapeType.arrow:
        canvas.drawLine(localStart, localEnd, paint);
        final angle = math.atan2(localEnd.dy - localStart.dy, localEnd.dx - localStart.dx);
        final arrowLength = math.max(shape.strokeWidth * 4.0, 12.0);
        const arrowAngle = math.pi / 6;

        final p1 = Offset(
          localEnd.dx - arrowLength * math.cos(angle - arrowAngle),
          localEnd.dy - arrowLength * math.sin(angle - arrowAngle),
        );
        final p2 = Offset(
          localEnd.dx - arrowLength * math.cos(angle + arrowAngle),
          localEnd.dy - arrowLength * math.sin(angle + arrowAngle),
        );

        canvas.drawLine(localEnd, p1, paint);
        canvas.drawLine(localEnd, p2, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SingleShapePainter oldDelegate) {
    return oldDelegate.shape.start != shape.start ||
        oldDelegate.shape.end != shape.end ||
        oldDelegate.shape.color != shape.color ||
        oldDelegate.shape.strokeWidth != shape.strokeWidth ||
        oldDelegate.isSelected != isSelected ||
        oldDelegate.scale != scale;
  }
}

class _ShapeWidget extends StatefulWidget {
  final DrawnShape shape;
  final bool isSelected;
  final TransformationController? transformationController;
  final VoidCallback onSelect;
  final VoidCallback onDeselect;
  final void Function(Offset newStart, Offset newEnd) onUpdate;
  final void Function(Offset oldStart, Offset oldEnd) onModificationCommitted;
  final VoidCallback onDelete;

  const _ShapeWidget({
    super.key,
    required this.shape,
    required this.isSelected,
    this.transformationController,
    required this.onSelect,
    required this.onDeselect,
    required this.onUpdate,
    required this.onModificationCommitted,
    required this.onDelete,
  });

  @override
  State<_ShapeWidget> createState() => _ShapeWidgetState();
}

class _ShapeWidgetState extends State<_ShapeWidget> {
  static const double kPadding = 48.0;

  Offset? _dragStartOriginalStart;
  Offset? _dragStartOriginalEnd;

  void _startDrag() {
    _dragStartOriginalStart = widget.shape.start;
    _dragStartOriginalEnd = widget.shape.end;
  }

  void _endDrag() {
    if (_dragStartOriginalStart != null && _dragStartOriginalEnd != null) {
      widget.onModificationCommitted(_dragStartOriginalStart!, _dragStartOriginalEnd!);
    }
    _dragStartOriginalStart = null;
    _dragStartOriginalEnd = null;
  }

  @override
  Widget build(BuildContext context) {
    final shape = widget.shape;
    final minX = math.min(shape.start.dx, shape.end.dx);
    final maxX = math.max(shape.start.dx, shape.end.dx);
    final minY = math.min(shape.start.dy, shape.end.dy);
    final maxY = math.max(shape.start.dy, shape.end.dy);
    final width = maxX - minX;
    final height = maxY - minY;

    final boxWidth = width + kPadding * 2;
    final boxHeight = height + kPadding * 2;

    final scale = (widget.transformationController?.value.getMaxScaleOnAxis() ?? 1.0).clamp(0.2, 5.0);
    final handleTouchSize = 40.0 / scale;
    final handleVisualSize = 14.0 / scale;
    final handleBorderWidth = 2.0 / scale;

    final localStart = Offset(
      shape.start.dx - minX + kPadding,
      shape.start.dy - minY + kPadding,
    );
    final localEnd = Offset(
      shape.end.dx - minX + kPadding,
      shape.end.dy - minY + kPadding,
    );

    final isRectOrCircle = shape.type == ShapeType.rectangle || shape.type == ShapeType.circle;

    Widget content = SizedBox(
      width: boxWidth,
      height: boxHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Paint shape and selection border
          Positioned.fill(
            child: CustomPaint(
              painter: _SingleShapePainter(
                shape: shape,
                isSelected: widget.isSelected,
                kPadding: kPadding,
                scale: scale,
              ),
            ),
          ),

          // 2. Body interaction:
          if (widget.isSelected)
            Positioned(
              left: kPadding,
              top: kPadding,
              width: math.max(width, 24.0),
              height: math.max(height, 24.0),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / scale;
                  widget.onUpdate(
                    widget.shape.start + deltaDoc,
                    widget.shape.end + deltaDoc,
                  );
                  setState(() {});
                },
                onPanEnd: (_) => _endDrag(),
                child: const SizedBox.expand(),
              ),
            )
          else
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (details) {
                  final local = details.localPosition;
                  final docPos = Offset(minX - kPadding + local.dx, minY - kPadding + local.dy);
                  if (DrawingController.isPointNearShape(docPos, widget.shape, 24.0)) {
                    widget.onSelect();
                  }
                },
                child: const SizedBox.expand(),
              ),
            ),

          // 3. Handles and controls when selected
          if (widget.isSelected) ...[
            if (isRectOrCircle) ...[
              // 4 Corner Handles: TL, TR, BL, BR
              _ShapeHandle(
                position: const Offset(kPadding, kPadding),
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / scale;
                  final newLeft = math.min(minX + deltaDoc.dx, maxX - 12.0);
                  final newTop = math.min(minY + deltaDoc.dy, maxY - 12.0);
                  widget.onUpdate(Offset(newLeft, newTop), Offset(maxX, maxY));
                  setState(() {});
                },
                onPanEnd: _endDrag,
              ),
              _ShapeHandle(
                position: Offset(kPadding + width, kPadding),
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / scale;
                  final newRight = math.max(maxX + deltaDoc.dx, minX + 12.0);
                  final newTop = math.min(minY + deltaDoc.dy, maxY - 12.0);
                  widget.onUpdate(Offset(minX, newTop), Offset(newRight, maxY));
                  setState(() {});
                },
                onPanEnd: _endDrag,
              ),
              _ShapeHandle(
                position: Offset(kPadding, kPadding + height),
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / scale;
                  final newLeft = math.min(minX + deltaDoc.dx, maxX - 12.0);
                  final newBottom = math.max(maxY + deltaDoc.dy, minY + 12.0);
                  widget.onUpdate(Offset(newLeft, minY), Offset(maxX, newBottom));
                  setState(() {});
                },
                onPanEnd: _endDrag,
              ),
              _ShapeHandle(
                position: Offset(kPadding + width, kPadding + height),
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / scale;
                  final newRight = math.max(maxX + deltaDoc.dx, minX + 12.0);
                  final newBottom = math.max(maxY + deltaDoc.dy, minY + 12.0);
                  widget.onUpdate(Offset(minX, minY), Offset(newRight, newBottom));
                  setState(() {});
                },
                onPanEnd: _endDrag,
              ),
            ] else ...[
              // Line / Arrow: 2 Endpoint Handles
              _ShapeHandle(
                position: localStart,
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / scale;
                  widget.onUpdate(widget.shape.start + deltaDoc, widget.shape.end);
                  setState(() {});
                },
                onPanEnd: _endDrag,
              ),
              _ShapeHandle(
                position: localEnd,
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / scale;
                  widget.onUpdate(widget.shape.start, widget.shape.end + deltaDoc);
                  setState(() {});
                },
                onPanEnd: _endDrag,
              ),
            ],
          ],
        ],
      ),
    );

    if (widget.isSelected) {
      return TapRegion(
        groupId: kEditableElementRegionGroup,
        onTapOutside: (_) => widget.onDeselect(),
        child: content,
      );
    }

    return content;
  }
}

class _ImageWidget extends StatefulWidget {
  final DrawnImage image;
  final void Function(Offset newPos, double newW, double newH) onUpdate;
  final VoidCallback onDelete;

  const _ImageWidget({
    required this.image,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<_ImageWidget> createState() => _ImageWidgetState();
}

class _ImageWidgetState extends State<_ImageWidget> {
  late Offset _position;
  late double _width;
  late double _height;
  bool _isSelected = false;

  @override
  void initState() {
    super.initState();
    _position = widget.image.position;
    _width = widget.image.width;
    _height = widget.image.height;
  }

  @override
  void didUpdateWidget(covariant _ImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.position != widget.image.position) {
      _position = widget.image.position;
    }
    if (oldWidget.image.width != widget.image.width ||
        oldWidget.image.height != widget.image.height) {
      _width = widget.image.width;
      _height = widget.image.height;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onTap: () => setState(() => _isSelected = !_isSelected),
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
          widget.onUpdate(_position, _width, _height);
        },
        child: Container(
          width: _width,
          height: _height,
          decoration: BoxDecoration(
            border: _isSelected
                ? Border.all(color: Colors.blueAccent, width: 2)
                : Border.all(color: Colors.transparent, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Image.memory(
                    widget.image.imageBytes,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              if (_isSelected)
                Positioned(
                  top: -14,
                  right: -14,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onDelete,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Icon(Icons.close, size: 18, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextBoxWidget extends StatefulWidget {
  final DrawnTextBox textBox;
  final AppFontFamily textBoxFont;
  final bool isEditing;
  final VoidCallback onStartEditing;
  final VoidCallback onFinishEditing;
  final void Function(String newText, Offset newPosition, double newFontSize, double newWidth) onUpdate;
  final VoidCallback onDelete;

  const _TextBoxWidget({
    super.key,
    required this.textBox,
    this.textBoxFont = AppFontFamily.sansSerif,
    required this.isEditing,
    required this.onStartEditing,
    required this.onFinishEditing,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<_TextBoxWidget> createState() => _TextBoxWidgetState();
}

class _TextBoxWidgetState extends State<_TextBoxWidget> {
  late Offset _position;
  late TextEditingController _textController;
  late FocusNode _focusNode;
  late double _fontSize;
  late double _width;
  bool _isDeleting = false;

  String get _fontFamilyName {
    switch (widget.textBoxFont) {
      case AppFontFamily.serif:
        return 'serif';
      case AppFontFamily.monospace:
        return 'monospace';
      case AppFontFamily.sansSerif:
        return 'sans-serif';
    }
  }

  @override
  void initState() {
    super.initState();
    _position = widget.textBox.position;
    _fontSize = widget.textBox.fontSize;
    _width = widget.textBox.width ?? 220.0;
    _textController = TextEditingController(text: widget.textBox.text);
    _focusNode = FocusNode();
  }

  void _commitAndFinish() {
    if (_isDeleting || !widget.isEditing) return;
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _isDeleting = true;
      _focusNode.unfocus();
      widget.onDelete();
    } else {
      widget.onUpdate(text, _position, _fontSize, _width);
      _focusNode.unfocus();
      widget.onFinishEditing();
    }
  }

  @override
  void didUpdateWidget(covariant _TextBoxWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _position = widget.textBox.position;
    _fontSize = widget.textBox.fontSize;
    if (widget.textBox.width != null) {
      _width = widget.textBox.width!;
    }
    if (oldWidget.textBox.text != widget.textBox.text &&
        _textController.text != widget.textBox.text) {
      _textController.text = widget.textBox.text;
    }
    if (oldWidget.isEditing && !widget.isEditing) {
      final text = _textController.text.trim();
      if (text.isNotEmpty) {
        widget.textBox.text = text;
        widget.textBox.fontSize = _fontSize;
        widget.textBox.position = _position;
        widget.textBox.width = _width;
      }
    }
    if (!oldWidget.isEditing && widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEditing) {
      final textInput = Container(
        width: _width,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          border: Border.all(
            color: widget.textBox.color,
            width: 2.0,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top mini toolbar: Drag handle
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    setState(() {
                      _position += details.delta;
                    });
                    widget.onUpdate(_textController.text, _position, _fontSize, _width);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.textBox.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.drag_indicator_rounded, size: 14, color: widget.textBox.color),
                        const SizedBox(width: 3),
                        Text(
                          'Drag',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: widget.textBox.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _textController,
              focusNode: _focusNode,
              autofocus: true,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              cursorColor: widget.textBox.color,
              style: TextStyle(
                color: widget.textBox.color,
                fontSize: _fontSize,
                fontWeight: FontWeight.w600,
                height: 1.3,
                fontFamily: _fontFamilyName,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: 'Type text...',
                hintStyle: TextStyle(color: Colors.black38, fontSize: _fontSize),
              ),
              onChanged: (val) {
                widget.onUpdate(val, _position, _fontSize, _width);
              },
            ),
          ],
        ),
      );

      return TapRegion(
        groupId: kEditableElementRegionGroup,
        onTapOutside: (_) => _commitAndFinish(),
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              textInput,
              // Right-edge horizontal resize handle (generous 48px touch target, safe inside TapRegion)
              Positioned(
                right: -24,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      setState(() {
                        _width = math.max(80.0, _width + details.delta.dx);
                      });
                      widget.onUpdate(_textController.text, _position, _fontSize, _width);
                    },
                    child: Container(
                      width: 48,
                      height: 56,
                      alignment: Alignment.center,
                      color: Colors.transparent,
                      child: Container(
                        width: 7,
                        height: 28,
                        decoration: BoxDecoration(
                          color: widget.textBox.color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.textBox.text.isEmpty) {
      return const SizedBox.shrink();
    }

    // Viewing mode: Body pan gesture and Resize handle are separate siblings in the Stack
    // to avoid gesture arena conflicts
    final textContent = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStartEditing,
      onPanUpdate: (details) {
        setState(() {
          _position += details.delta;
        });
        widget.onUpdate(widget.textBox.text, _position, _fontSize, _width);
      },
      child: Container(
        width: _width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.textBox.color.withValues(alpha: 0.3),
            width: 1.0,
          ),
        ),
        child: Text(
          widget.textBox.text,
          softWrap: true,
          style: TextStyle(
            color: widget.textBox.color,
            fontSize: widget.textBox.fontSize,
            fontWeight: FontWeight.w500,
            height: 1.3,
            fontFamily: _fontFamilyName,
          ),
        ),
      ),
    );

    final resizeHandle = Positioned(
      right: -24,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) {
            setState(() {
              _width = math.max(80.0, _width + details.delta.dx);
            });
            widget.onUpdate(widget.textBox.text, _position, _fontSize, _width);
          },
          child: Container(
            width: 48,
            height: 56,
            alignment: Alignment.center,
            color: Colors.transparent,
            child: Container(
              width: 7,
              height: 28,
              decoration: BoxDecoration(
                color: widget.textBox.color.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          textContent,
          resizeHandle,
        ],
      ),
    );
  }
}

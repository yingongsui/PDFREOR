import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../controllers/drawing_controller.dart';
import '../models/editor_models.dart';
import '../services/editor_settings_service.dart';
import 'canvas/editor_canvas_painters.dart';
import 'canvas/stylus_drawing_gesture_recognizer.dart';
import 'pdf_canvas_items.dart';

export 'canvas/stylus_drawing_gesture_recognizer.dart'
    show StylusDrawingGestureRecognizer;
export 'pdf_canvas_items.dart'
    show kEditableElementRegionGroup, DocumentStack, RenderDocumentStack;

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
  final ValueChanged<Offset>? onAddLatexBoxRequested;
  final VoidCallback? onShapeCompleted;
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
    this.onAddLatexBoxRequested,
    this.onShapeCompleted,
    this.onStylusDetected,
    this.onStylusDrawStarted,
    this.textBoxFont = AppFontFamily.sansSerif,
  });

  @override
  State<PdfEditorCanvas> createState() => _PdfEditorCanvasState();
}

class _PdfEditorCanvasState extends State<PdfEditorCanvas> {
  late Listenable _savedPaintListenable;
  late Listenable _activePaintListenable;
  final SavedLayerPictureCache _pictureCache = SavedLayerPictureCache();

  @override
  void initState() {
    super.initState();
    widget.controller.savedLayerListenable.addListener(_onSavedLayerChanged);
    _rebuildPaintListenables();
  }

  void _onSavedLayerChanged() {
    _pictureCache.invalidate();
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
      widget.activeTool == EditorTool.textBox ||
      widget.activeTool == EditorTool.latexBox;

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
        if (selectedShape != null && paddedShapeBounds(selectedShape).contains(docPos)) {
          return;
        }
      }

      if (_selectedStrokeId != null) {
        final selectedStroke = widget.controller.strokes.cast<DrawingStroke?>().firstWhere(
          (s) => s?.id == _selectedStrokeId,
          orElse: () => null,
        );
        if (selectedStroke != null && paddedStrokeBounds(selectedStroke).contains(docPos)) {
          return;
        }
      }

      final hitShape = widget.controller.hitTestShape(docPos, 24.0);
      if (hitShape != null) {
        _setSelectedShape(hitShape.id);
        _setSelectedStroke(null);
        _setSelectedTextAnnotation(null);
        return;
      }

      final hitStroke = widget.controller.hitTestStroke(docPos, 20.0);
      if (hitStroke != null) {
        _setSelectedStroke(hitStroke.id);
        _setSelectedShape(null);
        _setSelectedTextAnnotation(null);
        return;
      }

      final hitTa = widget.controller.hitTestTextAnnotation(docPos, 6.0);
      if (hitTa != null) {
        _setSelectedTextAnnotation(hitTa.id);
        _setSelectedShape(null);
        _setSelectedStroke(null);
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
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      return;
    }
    _checkPointer(event);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      _checkPointer(event);
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      _checkPointer(event);
    }
  }

  @override
  void didUpdateWidget(covariant PdfEditorCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.savedLayerListenable.removeListener(_onSavedLayerChanged);
      widget.controller.savedLayerListenable.addListener(_onSavedLayerChanged);
      _pictureCache.invalidate();
    }
    if (widget.controller != oldWidget.controller ||
        widget.transformationController != oldWidget.transformationController) {
      _rebuildPaintListenables();
    }
  }

  @override
  void dispose() {
    widget.controller.savedLayerListenable.removeListener(_onSavedLayerChanged);
    _pictureCache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedStroke = _selectedStrokeId == null
        ? null
        : widget.controller.strokes.cast<DrawingStroke?>().firstWhere(
            (s) => s?.id == _selectedStrokeId,
            orElse: () => null,
          );

    final hasWidgetAnnotations = widget.controller.shapes.isNotEmpty ||
        widget.controller.images.isNotEmpty ||
        widget.controller.textBoxes.isNotEmpty ||
        selectedStroke != null;

    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        // 1a. Committed strokes & text annotations cached as per-page Pictures with frustum culling
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                isComplex: true,
                painter: SavedAnnotationsPainter(
                  repaint: _savedPaintListenable,
                  controller: widget.controller,
                  pictureCache: _pictureCache,
                  transformationController: widget.transformationController,
                  selectedStrokeId: _selectedStrokeId,
                  selectedTextAnnotationId: _selectedTextAnnotationId,
                ),
              ),
            ),
          ),
        ),
        // 1b. Active in-progress stroke / shape preview layer (isolated 240Hz RepaintBoundary)
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: ActiveAnnotationPainter(
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
        // 2-4. Interactive widget annotations
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
            child: DocumentStack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                if (selectedStroke != null)
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: widget.controller.savedLayerListenable,
                      builder: (context, _) => _buildSelectedStrokeOverlay(selectedStroke),
                    ),
                  ),
                for (final shape in widget.controller.shapes)
                  _buildShapeWidget(shape),
                for (final img in widget.controller.images)
                  Positioned(
                    key: ValueKey('img_pos_${img.id}'),
                    left: img.position.dx,
                    top: img.position.dy,
                    child: ImageCanvasItem(
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
        // Top banner for one-shot shape drawing
        if (widget.oneShotShape != null)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
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
                        widget.oneShotShape!.icon,
                        size: 18,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Drag with finger to draw ${widget.oneShotShape!.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
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

    if ((widget.activeTool == EditorTool.textBox || widget.activeTool == EditorTool.latexBox) &&
        widget.oneShotShape == null) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: _checkPointer,
        onPointerDown: _checkPointer,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) {
            final docPos = widget.transformationController?.toScene(details.localPosition) ??
                details.localPosition;
            if (widget.activeTool == EditorTool.latexBox) {
              widget.onAddLatexBoxRequested?.call(docPos);
            } else {
              widget.onAddTextBoxRequested(docPos);
            }
          },
          child: content,
        ),
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
              onShapeCompleted: widget.onShapeCompleted,
              selectedShapeId: _selectedShapeId,
              selectedStrokeId: _selectedStrokeId,
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
                onShapeCompleted: widget.onShapeCompleted,
                selectedShapeId: _selectedShapeId,
                selectedStrokeId: _selectedStrokeId,
              );
            },
          ),
        },
        child: content,
      ),
    );
  }

  Widget _buildShapeWidget(DrawnShape shape) {
    final bounds = paddedShapeBounds(shape);

    return Positioned(
      key: ValueKey('shape_${shape.id}'),
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
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

  Widget _buildSelectedStrokeOverlay(DrawingStroke stroke) {
    if (!widget.controller.strokes.contains(stroke) || stroke.points.isEmpty) {
      return const SizedBox.shrink();
    }
    final bounds = paddedStrokeBounds(stroke);
    return DocumentStack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Positioned(
          key: ValueKey('stroke_pos_${stroke.id}'),
          left: bounds.left,
          top: bounds.top,
          width: bounds.width,
          height: bounds.height,
          child: _SelectedStrokeDragItem(
            key: ValueKey('stroke_drag_${stroke.id}'),
            stroke: stroke,
            transformationController: widget.transformationController,
            onMove: (delta) => widget.controller.moveStroke(stroke, delta),
            onMoveCommitted: (totalDelta) =>
                widget.controller.recordStrokeMove(stroke, totalDelta),
          ),
        ),
      ],
    );
  }
}

class _SelectedStrokeDragItem extends StatefulWidget {
  final DrawingStroke stroke;
  final TransformationController? transformationController;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onMoveCommitted;

  const _SelectedStrokeDragItem({
    super.key,
    required this.stroke,
    this.transformationController,
    required this.onMove,
    required this.onMoveCommitted,
  });

  @override
  State<_SelectedStrokeDragItem> createState() => _SelectedStrokeDragItemState();
}

class _SelectedStrokeDragItemState extends State<_SelectedStrokeDragItem> {
  Offset _totalDelta = Offset.zero;

  double get _currentScale =>
      (widget.transformationController?.value.getMaxScaleOnAxis() ?? 1.0)
          .clamp(0.2, 5.0);

  void _commitDrag() {
    if (_totalDelta != Offset.zero) {
      widget.onMoveCommitted(_totalDelta);
      _totalDelta = Offset.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: kEditableElementRegionGroup,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            _totalDelta = Offset.zero;
          },
          onPanUpdate: (details) {
            final docDelta = details.delta / _currentScale;
            if (docDelta == Offset.zero) return;
            _totalDelta += docDelta;
            widget.onMove(docDelta);
          },
          onPanEnd: (_) => _commitDrag(),
          onPanCancel: _commitDrag,
        ),
      ),
    );
  }
}

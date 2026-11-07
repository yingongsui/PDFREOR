import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../controllers/drawing_controller.dart';
import '../models/editor_models.dart';
import '../services/editor_settings_service.dart';

/// TapRegion group id shared by editable elements and the top property bar
const String kEditableElementRegionGroup = 'EditableElementRegionGroup';

class _CanvasHandle extends StatelessWidget {
  final Offset position;
  final double touchSize;
  final double visualSize;
  final double borderWidth;
  final void Function(DragStartDetails details)? onPanStart;
  final void Function(DragUpdateDetails details) onPanUpdate;
  final VoidCallback? onPanEnd;

  const _CanvasHandle({
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
  final ShapeType type;
  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;
  final bool isSelected;
  final double kPadding;
  final double scale;

  _SingleShapePainter({
    required DrawnShape shape,
    required this.isSelected,
    required this.kPadding,
    required this.scale,
  })  : type = shape.type,
        start = shape.start,
        end = shape.end,
        color = shape.color,
        strokeWidth = shape.strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final minX = math.min(start.dx, end.dx);
    final maxX = math.max(start.dx, end.dx);
    final minY = math.min(start.dy, end.dy);
    final maxY = math.max(start.dy, end.dy);
    final width = maxX - minX;
    final height = maxY - minY;

    final localStart = Offset(
      start.dx - minX + kPadding,
      start.dy - minY + kPadding,
    );
    final localEnd = Offset(
      end.dx - minX + kPadding,
      end.dy - minY + kPadding,
    );

    final shapeRect = Rect.fromLTWH(kPadding, kPadding, width, height);

    if (isSelected) {
      final highlightPaint = Paint()
        ..color = const Color(0xFF2196F3).withValues(alpha: 0.5)
        ..strokeWidth = math.max(1.0, 1.5 / scale)
        ..style = PaintingStyle.stroke;

      final bounds = shapeRect.inflate(4.0 / scale);
      canvas.drawRect(bounds, highlightPaint);
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    paintShapeOnCanvas(canvas, type, localStart, localEnd, paint);
  }

  @override
  bool shouldRepaint(covariant _SingleShapePainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.isSelected != isSelected ||
        oldDelegate.scale != scale;
  }
}

class ShapeCanvasItem extends StatefulWidget {
  final DrawnShape shape;
  final bool isSelected;
  final TransformationController? transformationController;
  final VoidCallback onSelect;
  final VoidCallback onDeselect;
  final void Function(Offset newStart, Offset newEnd) onUpdate;
  final void Function(Offset oldStart, Offset oldEnd) onModificationCommitted;
  final VoidCallback onDelete;

  const ShapeCanvasItem({
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
  State<ShapeCanvasItem> createState() => _ShapeCanvasItemState();
}

class _ShapeCanvasItemState extends State<ShapeCanvasItem> {
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

  double get _currentScale =>
      (widget.transformationController?.value.getMaxScaleOnAxis() ?? 1.0).clamp(0.2, 5.0);

  @override
  Widget build(BuildContext context) {
    final tc = widget.transformationController;
    if (widget.isSelected && tc != null) {
      return ValueListenableBuilder<Matrix4>(
        valueListenable: tc,
        builder: (context, _, _) => _buildShapeBody(),
      );
    }
    return _buildShapeBody();
  }

  Widget _buildShapeBody() {
    final shape = widget.shape;
    final minX = math.min(shape.start.dx, shape.end.dx);
    final maxX = math.max(shape.start.dx, shape.end.dx);
    final minY = math.min(shape.start.dy, shape.end.dy);
    final maxY = math.max(shape.start.dy, shape.end.dy);
    final width = maxX - minX;
    final height = maxY - minY;

    final boxWidth = width + kPadding * 2;
    final boxHeight = height + kPadding * 2;

    final scale = _currentScale;
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
                  final deltaDoc = details.delta / _currentScale;
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
          if (widget.isSelected) ...[
            if (isRectOrCircle) ...[
              _CanvasHandle(
                position: const Offset(kPadding, kPadding),
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / _currentScale;
                  final newLeft = math.min(minX + deltaDoc.dx, maxX - 12.0);
                  final newTop = math.min(minY + deltaDoc.dy, maxY - 12.0);
                  widget.onUpdate(Offset(newLeft, newTop), Offset(maxX, maxY));
                  setState(() {});
                },
                onPanEnd: _endDrag,
              ),
              _CanvasHandle(
                position: Offset(kPadding + width, kPadding),
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / _currentScale;
                  final newRight = math.max(maxX + deltaDoc.dx, minX + 12.0);
                  final newTop = math.min(minY + deltaDoc.dy, maxY - 12.0);
                  widget.onUpdate(Offset(minX, newTop), Offset(newRight, maxY));
                  setState(() {});
                },
                onPanEnd: _endDrag,
              ),
              _CanvasHandle(
                position: Offset(kPadding, kPadding + height),
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / _currentScale;
                  final newLeft = math.min(minX + deltaDoc.dx, maxX - 12.0);
                  final newBottom = math.max(maxY + deltaDoc.dy, minY + 12.0);
                  widget.onUpdate(Offset(newLeft, minY), Offset(maxX, newBottom));
                  setState(() {});
                },
                onPanEnd: _endDrag,
              ),
              _CanvasHandle(
                position: Offset(kPadding + width, kPadding + height),
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / _currentScale;
                  final newRight = math.max(maxX + deltaDoc.dx, minX + 12.0);
                  final newBottom = math.max(maxY + deltaDoc.dy, minY + 12.0);
                  widget.onUpdate(Offset(minX, minY), Offset(newRight, newBottom));
                  setState(() {});
                },
                onPanEnd: _endDrag,
              ),
            ] else ...[
              _CanvasHandle(
                position: localStart,
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / _currentScale;
                  widget.onUpdate(widget.shape.start + deltaDoc, widget.shape.end);
                  setState(() {});
                },
                onPanEnd: _endDrag,
              ),
              _CanvasHandle(
                position: localEnd,
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / _currentScale;
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

class ImageCanvasItem extends StatefulWidget {
  final DrawnImage image;
  final TransformationController? transformationController;
  final void Function(Offset newPos, double newW, double newH) onUpdate;
  final void Function(Offset oldPos, double oldW, double oldH) onModificationCommitted;
  final VoidCallback onDelete;

  const ImageCanvasItem({
    super.key,
    required this.image,
    this.transformationController,
    required this.onUpdate,
    required this.onModificationCommitted,
    required this.onDelete,
  });

  @override
  State<ImageCanvasItem> createState() => _ImageCanvasItemState();
}

class _ImageCanvasItemState extends State<ImageCanvasItem> {
  late Offset _position;
  late double _width;
  late double _height;
  bool _isSelected = false;

  Offset? _dragOrigPos;
  double? _dragOrigWidth;
  double? _dragOrigHeight;

  @override
  void initState() {
    super.initState();
    _position = widget.image.position;
    _width = widget.image.width;
    _height = widget.image.height;
  }

  @override
  void didUpdateWidget(covariant ImageCanvasItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    _position = widget.image.position;
    _width = widget.image.width;
    _height = widget.image.height;
  }

  void _startModification() {
    _dragOrigPos = _position;
    _dragOrigWidth = _width;
    _dragOrigHeight = _height;
  }

  void _commitModification() {
    if (_dragOrigPos != null && _dragOrigWidth != null && _dragOrigHeight != null) {
      widget.onModificationCommitted(_dragOrigPos!, _dragOrigWidth!, _dragOrigHeight!);
    }
    _dragOrigPos = null;
    _dragOrigWidth = null;
    _dragOrigHeight = null;
  }

  double get _currentScale =>
      (widget.transformationController?.value.getMaxScaleOnAxis() ?? 1.0).clamp(0.2, 5.0);

  @override
  Widget build(BuildContext context) {
    final tc = widget.transformationController;
    if (_isSelected && tc != null) {
      return ValueListenableBuilder<Matrix4>(
        valueListenable: tc,
        builder: (context, _, _) => _buildImageBody(),
      );
    }
    return _buildImageBody();
  }

  Widget _buildImageBody() {
    final scale = _currentScale;
    final handleTouchSize = 40.0 / scale;
    final handleVisualSize = 14.0 / scale;
    final handleBorderWidth = 2.0 / scale;
    final aspect = _height > 0 ? (_width / _height) : 1.0;

    Widget body = GestureDetector(
      onTap: () => setState(() => _isSelected = !_isSelected),
      onPanStart: (_) => _startModification(),
      onPanUpdate: (details) {
        final deltaDoc = details.delta / _currentScale;
        setState(() {
          _position += deltaDoc;
        });
        widget.onUpdate(_position, _width, _height);
      },
      onPanEnd: (_) => _commitModification(),
      child: Container(
        width: _width,
        height: _height,
        decoration: BoxDecoration(
          border: _isSelected
              ? Border.all(color: Colors.blueAccent, width: math.max(1.0, 2.0 / scale))
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
            if (_isSelected) ...[
              Positioned(
                top: -14 / scale,
                right: -14 / scale,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onDelete,
                  child: Container(
                    width: 32 / scale,
                    height: 32 / scale,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    child: Icon(Icons.close, size: 18 / scale, color: Colors.white),
                  ),
                ),
              ),
              _CanvasHandle(
                position: Offset(_width, _height),
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startModification(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / _currentScale;
                  setState(() {
                    _width = math.max(36.0, _width + deltaDoc.dx);
                    _height = math.max(24.0, _width / aspect);
                  });
                  widget.onUpdate(_position, _width, _height);
                },
                onPanEnd: _commitModification,
              ),
            ],
          ],
        ),
      ),
    );

    if (_isSelected) {
      body = TapRegion(
        groupId: kEditableElementRegionGroup,
        onTapOutside: (_) {
          if (mounted) setState(() => _isSelected = false);
        },
        child: body,
      );
    }

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: body,
    );
  }
}

class TextBoxCanvasItem extends StatefulWidget {
  final DrawnTextBox textBox;
  final AppFontFamily textBoxFont;
  final TransformationController? transformationController;
  final bool isEditing;
  final VoidCallback onStartEditing;
  final VoidCallback onFinishEditing;
  final void Function(String newText, Offset newPosition, double newFontSize, double newWidth) onUpdate;
  final void Function(Offset oldPosition, double? oldWidth) onLayoutModificationCommitted;
  final VoidCallback onDelete;

  const TextBoxCanvasItem({
    super.key,
    required this.textBox,
    this.textBoxFont = AppFontFamily.sansSerif,
    this.transformationController,
    required this.isEditing,
    required this.onStartEditing,
    required this.onFinishEditing,
    required this.onUpdate,
    required this.onLayoutModificationCommitted,
    required this.onDelete,
  });

  @override
  State<TextBoxCanvasItem> createState() => _TextBoxCanvasItemState();
}

class _TextBoxCanvasItemState extends State<TextBoxCanvasItem> {
  final GlobalKey _repaintKey = GlobalKey();
  late Offset _position;
  late TextEditingController _textController;
  late FocusNode _focusNode;
  late double _fontSize;
  late double _width;
  bool _isDeleting = false;

  Offset? _dragOrigPosition;
  double? _dragOrigWidth;
  String? _lastCapturedText;
  double? _lastCapturedFontSize;
  Color? _lastCapturedColor;
  double? _lastCapturedWidth;

  double get _currentScale =>
      (widget.transformationController?.value.getMaxScaleOnAxis() ?? 1.0).clamp(0.2, 5.0);

  Future<void> _captureRenderedLatex() async {
    if (!widget.textBox.isLatex || !mounted) return;
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        final bytes = byteData?.buffer.asUint8List();
        if (bytes != null && mounted) {
          widget.textBox.renderedImageBytes = bytes;
          widget.textBox.renderedSize = boundary.size;
          _lastCapturedText = widget.textBox.text;
          _lastCapturedFontSize = widget.textBox.fontSize;
          _lastCapturedColor = widget.textBox.color;
          _lastCapturedWidth = _width;
        }
      } finally {
        image.dispose();
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _position = widget.textBox.position;
    _fontSize = widget.textBox.fontSize;
    _width = widget.textBox.width ?? (widget.textBox.isLatex ? 250.0 : 220.0);
    _textController = TextEditingController(text: widget.textBox.text);
    _focusNode = FocusNode();
    if (widget.textBox.isLatex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _captureRenderedLatex());
    }
  }

  void _insertOperator(String op) {
    final text = _textController.text;
    final selection = _textController.selection;
    final int start = selection.isValid ? selection.start : text.length;
    final int end = selection.isValid ? selection.end : text.length;

    final newText = text.replaceRange(start, end, op);
    final newCursorPos = start + op.length;

    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );

    setState(() {});
    widget.onUpdate(newText, _position, _fontSize, _width);
  }

  void _startLayoutDrag() {
    _dragOrigPosition = _position;
    _dragOrigWidth = widget.textBox.width ?? _width;
  }

  void _commitLayoutDrag() {
    if (_dragOrigPosition != null) {
      widget.onLayoutModificationCommitted(_dragOrigPosition!, _dragOrigWidth);
    }
    _dragOrigPosition = null;
    _dragOrigWidth = null;
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
      if (widget.textBox.isLatex) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _captureRenderedLatex());
      }
    }
  }

  @override
  void didUpdateWidget(covariant TextBoxCanvasItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    _position = widget.textBox.position;
    _fontSize = widget.textBox.fontSize;
    if (widget.textBox.width != null) {
      _width = widget.textBox.width!;
    }
    if ((!widget.isEditing || oldWidget.textBox != widget.textBox) &&
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
    if (widget.textBox.isLatex && !widget.isEditing) {
      final needsRecapture = (oldWidget.isEditing && !widget.isEditing) ||
          widget.textBox.renderedImageBytes == null ||
          _lastCapturedText != widget.textBox.text ||
          _lastCapturedFontSize != widget.textBox.fontSize ||
          _lastCapturedColor != widget.textBox.color ||
          _lastCapturedWidth != _width;
      if (needsRecapture) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _captureRenderedLatex());
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
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => _startLayoutDrag(),
                  onPanUpdate: (details) {
                    setState(() {
                      _position += details.delta / _currentScale;
                    });
                    widget.onUpdate(_textController.text, _position, _fontSize, _width);
                  },
                  onPanEnd: (_) => _commitLayoutDrag(),
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
                if (widget.textBox.isLatex) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.textBox.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.functions_rounded, size: 12, color: widget.textBox.color),
                        const SizedBox(width: 3),
                        Text(
                          'LaTeX',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: widget.textBox.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            if (widget.textBox.isLatex) ...[
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(minHeight: 38),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: widget.textBox.color.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Math.tex(
                      _textController.text.trim().isEmpty ? r'\dots' : _textController.text,
                      textStyle: TextStyle(
                        color: widget.textBox.color,
                        fontSize: _fontSize,
                      ),
                      mathStyle: MathStyle.display,
                      onErrorFallback: (err) => Text(
                        err.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: math.max(10.0, _fontSize * 0.65),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ValueListenableBuilder<EditorSettings>(
                valueListenable: EditorSettingsService.settingsNotifier,
                builder: (context, settings, _) {
                  final ops = settings.latexQuickOperators;
                  if (ops.isEmpty) return const SizedBox.shrink();
                  return Container(
                    height: 58,
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: ops.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 5),
                      itemBuilder: (context, idx) {
                        final op = ops[idx];
                        return InkWell(
                          borderRadius: BorderRadius.circular(5),
                          onTap: () => _insertOperator(op),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: widget.textBox.color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: widget.textBox.color.withValues(alpha: 0.22),
                                width: 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Math.tex(
                              op,
                              textStyle: TextStyle(
                                fontSize: 13,
                                color: widget.textBox.color,
                              ),
                              mathStyle: MathStyle.display,
                              onErrorFallback: (_) => Text(
                                op,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: widget.textBox.color,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ],
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
                fontSize: widget.textBox.isLatex ? math.max(13.0, _fontSize * 0.85) : _fontSize,
                fontWeight: FontWeight.w600,
                height: 1.3,
                fontFamily: widget.textBox.isLatex ? 'monospace' : widget.textBoxFont.cssFontFamily,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: InputBorder.none,
                hintText: widget.textBox.isLatex ? r'Type LaTeX (e.g. \frac{a}{b})' : 'Type text...',
                hintStyle: TextStyle(color: Colors.black38, fontSize: _fontSize),
              ),
              onChanged: (val) {
                if (widget.textBox.isLatex) {
                  setState(() {});
                }
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
              Positioned(
                right: -24,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => _startLayoutDrag(),
                    onPanUpdate: (details) {
                      setState(() {
                        _width = math.max(80.0, _width + details.delta.dx / _currentScale);
                      });
                      widget.onUpdate(_textController.text, _position, _fontSize, _width);
                    },
                    onPanEnd: (_) => _commitLayoutDrag(),
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

    final Widget displayedWidget;
    if (widget.textBox.isLatex) {
      displayedWidget = Container(
        width: _width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.textBox.color.withValues(alpha: 0.3),
            width: 1.0,
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: RepaintBoundary(
            key: _repaintKey,
            child: Math.tex(
              widget.textBox.text,
              textStyle: TextStyle(
                color: widget.textBox.color,
                fontSize: widget.textBox.fontSize,
              ),
              mathStyle: MathStyle.display,
              onErrorFallback: (err) => Text(
                widget.textBox.text,
                style: TextStyle(
                  color: widget.textBox.color,
                  fontSize: widget.textBox.fontSize,
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      displayedWidget = Container(
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
            fontFamily: widget.textBoxFont.cssFontFamily,
          ),
        ),
      );
    }

    final textContent = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStartEditing,
      onPanStart: (_) => _startLayoutDrag(),
      onPanUpdate: (details) {
        setState(() {
          _position += details.delta / _currentScale;
        });
        widget.onUpdate(widget.textBox.text, _position, _fontSize, _width);
      },
      onPanEnd: (_) => _commitLayoutDrag(),
      child: displayedWidget,
    );

    final resizeHandle = Positioned(
      right: -24,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _startLayoutDrag(),
          onPanUpdate: (details) {
            setState(() {
              _width = math.max(80.0, _width + details.delta.dx / _currentScale);
            });
            widget.onUpdate(widget.textBox.text, _position, _fontSize, _width);
          },
          onPanEnd: (_) => _commitLayoutDrag(),
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


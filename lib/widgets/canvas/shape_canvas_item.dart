import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../controllers/drawing_controller.dart';
import '../../models/editor_models.dart';
import 'canvas_item_shared.dart';

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
    final minY = math.min(start.dy, end.dy);
    final maxX = math.max(start.dx, end.dx);
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
      widget.onModificationCommitted(
        _dragStartOriginalStart!,
        _dragStartOriginalEnd!,
      );
    }
    _dragStartOriginalStart = null;
    _dragStartOriginalEnd = null;
  }

  double get _currentScale =>
      (widget.transformationController?.value.getMaxScaleOnAxis() ?? 1.0)
          .clamp(0.2, 5.0);

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

    final isRectOrCircle = shape.type == ShapeType.rectangle ||
        shape.type == ShapeType.roundedRectangle ||
        shape.type == ShapeType.circle;

    final content = SizedBox(
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
                },
                onPanEnd: (_) => _endDrag(),
                onPanCancel: _endDrag,
                child: const SizedBox.expand(),
              ),
            )
          else
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (details) {
                  final local = details.localPosition;
                  final docPos = Offset(
                    minX - kPadding + local.dx,
                    minY - kPadding + local.dy,
                  );
                  if (DrawingController.isPointNearShape(
                    docPos,
                    widget.shape,
                    24.0,
                  )) {
                    widget.onSelect();
                  }
                },
                child: const SizedBox.expand(),
              ),
            ),
          if (widget.isSelected) ...[
            if (isRectOrCircle) ...[
              CanvasDragHandle(
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
                },
                onPanEnd: _endDrag,
              ),
              CanvasDragHandle(
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
                },
                onPanEnd: _endDrag,
              ),
              CanvasDragHandle(
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
                },
                onPanEnd: _endDrag,
              ),
              CanvasDragHandle(
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
                },
                onPanEnd: _endDrag,
              ),
            ] else ...[
              CanvasDragHandle(
                position: localStart,
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / _currentScale;
                  widget.onUpdate(
                    widget.shape.start + deltaDoc,
                    widget.shape.end,
                  );
                },
                onPanEnd: _endDrag,
              ),
              CanvasDragHandle(
                position: localEnd,
                touchSize: handleTouchSize,
                visualSize: handleVisualSize,
                borderWidth: handleBorderWidth,
                onPanStart: (_) => _startDrag(),
                onPanUpdate: (details) {
                  final deltaDoc = details.delta / _currentScale;
                  widget.onUpdate(
                    widget.shape.start,
                    widget.shape.end + deltaDoc,
                  );
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

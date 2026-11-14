import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/editor_models.dart';
import 'canvas_item_shared.dart';

class ImageCanvasItem extends StatefulWidget {
  final DrawnImage image;
  final TransformationController? transformationController;
  final void Function(Offset newPos, double newW, double newH) onUpdate;
  final void Function(Offset oldPos, double oldW, double oldH)
      onModificationCommitted;
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
  double? _dragOrigAspect;

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
    _dragOrigAspect = _height > 0 ? (_width / _height) : 1.0;
  }

  void _commitModification() {
    if (_dragOrigPos != null &&
        _dragOrigWidth != null &&
        _dragOrigHeight != null) {
      widget.onModificationCommitted(
        _dragOrigPos!,
        _dragOrigWidth!,
        _dragOrigHeight!,
      );
    }
    _dragOrigPos = null;
    _dragOrigWidth = null;
    _dragOrigHeight = null;
    _dragOrigAspect = null;
  }

  double get _currentScale =>
      (widget.transformationController?.value.getMaxScaleOnAxis() ?? 1.0)
          .clamp(0.2, 5.0);

  @override
  Widget build(BuildContext context) {
    final cachedImageWidget = ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.memory(
        widget.image.imageBytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      ),
    );

    final tc = widget.transformationController;
    if (_isSelected && tc != null) {
      return ValueListenableBuilder<Matrix4>(
        valueListenable: tc,
        child: cachedImageWidget,
        builder: (context, _, child) => _buildImageBody(child!),
      );
    }
    return _buildImageBody(cachedImageWidget);
  }

  Widget _buildImageBody(Widget imageContent) {
    final scale = _currentScale;
    final handleTouchSize = 40.0 / scale;
    final handleVisualSize = 14.0 / scale;
    final handleBorderWidth = 2.0 / scale;
    final aspect = _dragOrigAspect ?? (_height > 0 ? (_width / _height) : 1.0);

    Widget body = DocumentStack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _isSelected = !_isSelected),
          onPanStart: (_) => _startModification(),
          onPanUpdate: (details) {
            final deltaDoc = details.delta / _currentScale;
            _position += deltaDoc;
            widget.onUpdate(_position, _width, _height);
          },
          onPanEnd: (_) => _commitModification(),
          onPanCancel: _commitModification,
          child: Container(
            width: _width,
            height: _height,
            decoration: BoxDecoration(
              border: _isSelected
                  ? Border.all(
                      color: Colors.blueAccent,
                      width: math.max(1.0, 2.0 / scale),
                    )
                  : Border.all(color: Colors.transparent, width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: imageContent,
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
                child: Icon(
                  Icons.close,
                  size: 18 / scale,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          CanvasDragHandle(
            position: Offset(_width, _height),
            touchSize: handleTouchSize,
            visualSize: handleVisualSize,
            borderWidth: handleBorderWidth,
            onPanStart: (_) => _startModification(),
            onPanUpdate: (details) {
              final deltaDoc = details.delta / _currentScale;
              final nextW = math.max(36.0, _width + deltaDoc.dx);
              final nextH = math.max(24.0, nextW / aspect);
              _width = nextW;
              _height = nextH;
              widget.onUpdate(_position, _width, _height);
            },
            onPanEnd: _commitModification,
          ),
        ],
      ],
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

    return body;
  }
}

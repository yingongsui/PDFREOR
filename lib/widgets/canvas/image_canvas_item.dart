import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/editor_models.dart';
import 'canvas_item_shared.dart';

class ImageCanvasItem extends StatefulWidget {
  final DrawnImage image;
  final bool? isSelected;
  final TransformationController? transformationController;
  final VoidCallback? onSelect;
  final VoidCallback? onDeselect;
  final void Function(Offset newPos, double newW, double newH) onUpdate;
  final void Function(Offset oldPos, double oldW, double oldH)
      onModificationCommitted;
  final VoidCallback onDelete;

  const ImageCanvasItem({
    super.key,
    required this.image,
    this.isSelected,
    this.transformationController,
    this.onSelect,
    this.onDeselect,
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
  bool _localSelected = false;

  Offset? _dragOrigPos;
  double? _dragOrigWidth;
  double? _dragOrigHeight;
  double? _dragOrigAspect;

  bool get _effectiveSelected => widget.isSelected ?? _localSelected;

  void _toggleSelection() {
    if (widget.isSelected != null) {
      if (_effectiveSelected) {
        widget.onDeselect?.call();
      } else {
        widget.onSelect?.call();
      }
    } else {
      setState(() => _localSelected = !_localSelected);
    }
  }

  void _deselect() {
    if (widget.isSelected != null) {
      if (widget.isSelected!) {
        widget.onDeselect?.call();
      }
    } else if (_localSelected && mounted) {
      setState(() => _localSelected = false);
    }
  }

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
    if (_effectiveSelected && tc != null) {
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
    final isSelected = _effectiveSelected;

    Widget imageDetector = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleSelection,
      onPanStart: (_) => _startModification(),
      onPanUpdate: (details) {
        final deltaDoc = details.delta / _currentScale;
        setState(() {
          _position += deltaDoc;
        });
        widget.onUpdate(_position, _width, _height);
      },
      onPanEnd: (_) => _commitModification(),
      onPanCancel: _commitModification,
      child: Container(
        width: _width,
        height: _height,
        decoration: BoxDecoration(
          border: isSelected
              ? Border.all(
                  color: Colors.blueAccent,
                  width: math.max(1.0, 2.0 / scale),
                )
              : Border.all(color: Colors.transparent, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: imageContent,
      ),
    );

    if (isSelected) {
      imageDetector = TapRegion(
        groupId: kEditableElementRegionGroup,
        onTapOutside: (_) => _deselect(),
        child: imageDetector,
      );
    }

    return DocumentStack(
      clipBehavior: Clip.none,
      children: [
        imageDetector,
        if (isSelected) ...[
          Positioned(
            top: -14 / scale,
            right: -14 / scale,
            child: TapRegion(
              groupId: kEditableElementRegionGroup,
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
          ),
          CanvasDragHandle(
            position: Offset(_width, _height),
            touchSize: handleTouchSize,
            visualSize: handleVisualSize,
            borderWidth: handleBorderWidth,
            tapRegionGroupId: kEditableElementRegionGroup,
            onPanStart: (_) => _startModification(),
            onPanUpdate: (details) {
              final deltaDoc = details.delta / _currentScale;
              final deltaFromX = deltaDoc.dx;
              final deltaFromY = deltaDoc.dy * aspect;
              final deltaW =
                  deltaFromX.abs() >= deltaFromY.abs() ? deltaFromX : deltaFromY;
              final minW = math.max(36.0, 16.0 * aspect);
              final nextW = math.max(minW, _width + deltaW);
              final nextH = math.max(16.0, nextW / aspect);
              setState(() {
                _width = nextW;
                _height = nextH;
              });
              widget.onUpdate(_position, _width, _height);
            },
            onPanEnd: _commitModification,
          ),
        ],
      ],
    );
  }
}

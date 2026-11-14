import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// TapRegion group id shared by editable elements and the top property bar.
const String kEditableElementRegionGroup = 'EditableElementRegionGroup';

/// A Stack that does not reject hit-testing based on its own box size.
/// Required both for document-space overlays (where pages extend far beyond
/// viewport dimensions) and for item stacks with handles extending outside bounds.
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
  void updateRenderObject(
    BuildContext context,
    RenderDocumentStack renderObject,
  ) {
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

class CanvasDragHandle extends StatelessWidget {
  final Offset position;
  final double touchSize;
  final double visualSize;
  final double borderWidth;
  final void Function(DragStartDetails details)? onPanStart;
  final void Function(DragUpdateDetails details) onPanUpdate;
  final VoidCallback? onPanEnd;

  const CanvasDragHandle({
    super.key,
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
        onPanCancel: () => onPanEnd?.call(),
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

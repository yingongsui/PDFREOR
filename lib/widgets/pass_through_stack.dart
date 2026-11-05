import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A Stack that allows all overlapping children to receive hit testing.
///
/// Unlike standard [Stack], which stops testing siblings once a child reports a hit,
/// [PassThroughStack] continues testing lower siblings so both overlay canvases
/// (like [PdfEditorCanvas]) and underlying viewers (like [SfPdfViewer]) receive
/// pointer events in the gesture arena.
class PassThroughStack extends Stack {
  const PassThroughStack({
    super.key,
    super.alignment = AlignmentDirectional.topStart,
    super.textDirection,
    super.fit = StackFit.loose,
    super.clipBehavior = Clip.hardEdge,
    super.children = const <Widget>[],
  });

  @override
  RenderPassThroughStack createRenderObject(BuildContext context) {
    return RenderPassThroughStack(
      alignment: alignment,
      textDirection: textDirection ?? Directionality.maybeOf(context),
      fit: fit,
      clipBehavior: clipBehavior,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderPassThroughStack renderObject) {
    renderObject
      ..alignment = alignment
      ..textDirection = textDirection ?? Directionality.maybeOf(context)
      ..fit = fit
      ..clipBehavior = clipBehavior;
  }
}

class RenderPassThroughStack extends RenderStack {
  RenderPassThroughStack({
    super.alignment,
    super.textDirection,
    super.fit = StackFit.loose,
    super.clipBehavior = Clip.hardEdge,
  });

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var stackHit = false;
    RenderBox? child = lastChild;
    while (child != null) {
      final StackParentData childParentData = child.parentData! as StackParentData;
      final bool isHit = result.addWithPaintOffset(
        offset: childParentData.offset,
        position: position,
        hitTest: (BoxHitTestResult result, Offset? transformed) {
          assert(transformed == position - childParentData.offset);
          return child!.hitTest(result, position: transformed!);
        },
      );
      if (isHit) {
        stackHit = true;
      }
      child = childParentData.previousSibling;
    }
    return stackHit;
  }
}


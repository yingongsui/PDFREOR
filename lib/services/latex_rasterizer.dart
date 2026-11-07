import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class LatexRasterizerResult {
  final Uint8List bytes;
  final Size size;

  const LatexRasterizerResult({required this.bytes, required this.size});
}

class LatexRasterizer {
  static Future<LatexRasterizerResult?> rasterize({
    required String latex,
    required double fontSize,
    required Color color,
    double pixelRatio = 3.0,
  }) async {
    try {
      final widget = Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          color: Colors.transparent,
          child: Math.tex(
            latex,
            textStyle: TextStyle(
              fontSize: fontSize,
              color: color,
            ),
            mathStyle: MathStyle.display,
          ),
        ),
      );

      final repaintBoundary = RenderRepaintBoundary();
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final renderView = RenderView(
        view: view,
        child: RenderPositionedBox(alignment: Alignment.center, child: repaintBoundary),
        configuration: ViewConfiguration(
          logicalConstraints: const BoxConstraints(
            minWidth: 40,
            maxWidth: 1600,
            minHeight: 20,
            maxHeight: 1200,
          ),
          devicePixelRatio: pixelRatio,
        ),
      );

      final pipelineOwner = PipelineOwner()..rootNode = renderView;
      final focusManager = FocusManager();
      final buildOwner = BuildOwner(focusManager: focusManager);
      RenderObjectToWidgetElement<RenderBox>? rootElement;
      try {
        renderView.prepareInitialFrame();
        rootElement = RenderObjectToWidgetAdapter<RenderBox>(
          container: repaintBoundary,
          child: widget,
        ).attachToRenderTree(buildOwner);

        buildOwner.buildScope(rootElement);
        buildOwner.finalizeTree();
        pipelineOwner.flushLayout();
        pipelineOwner.flushCompositingBits();
        pipelineOwner.flushPaint();

        final ui.Image image = await repaintBoundary.toImage(pixelRatio: pixelRatio);
        Uint8List? bytes;
        try {
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          bytes = byteData?.buffer.asUint8List();
        } finally {
          image.dispose();
        }
        final size = repaintBoundary.size;

        if (bytes != null) {
          return LatexRasterizerResult(bytes: bytes, size: size);
        }
      } finally {
        if (rootElement != null) {
          try {
            RenderObjectToWidgetAdapter<RenderBox>(
              container: repaintBoundary,
            ).attachToRenderTree(buildOwner, rootElement);
            buildOwner.finalizeTree();
          } catch (_) {}
        }
        focusManager.dispose();
        renderView.dispose();
        pipelineOwner.dispose();
      }
    } catch (_) {}
    return null;
  }
}

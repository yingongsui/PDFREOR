import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'png_encoder.dart';

class LatexRasterizerResult {
  final Uint8List bytes;
  final Size size;
  final Offset offset;

  const LatexRasterizerResult({
    required this.bytes,
    required this.size,
    this.offset = Offset.zero,
  });
}

class LatexRasterizer {
  LatexRasterizer._();

  static const double _targetPdfDpi = 200.0;
  static const int _isolatePixelThreshold = 16384;

  /// Computes a rasterization pixelRatio matching ~200 physical DPI on the target PDF page,
  /// rounded to 0.05 increments so identical formulas share cached bitmaps.
  static double computeTargetPixelRatio(double pdfPointsPerLogicalPx) {
    if (pdfPointsPerLogicalPx <= 0 || !pdfPointsPerLogicalPx.isFinite) {
      return 2.0;
    }
    final rawRatio = (_targetPdfDpi / 72.0) * pdfPointsPerLogicalPx;
    final clamped = rawRatio.clamp(1.25, 2.5);
    return (clamped * 20.0).round() / 20.0;
  }

  /// Crops transparent margins, quantizes anti-aliased alpha to 16 clean levels,
  /// and encodes a compact PNG (Grayscale+Alpha when monochrome, RGBA otherwise).
  static LatexRasterizerResult? encodeCompactLatexPng({
    required Uint8List rawRgba,
    required int width,
    required int height,
    required Size logicalSize,
    required Color color,
    bool preserveMultiColor = false,
  }) {
    final int colorR = (color.r * 255.0).round().clamp(0, 255);
    final int colorG = (color.g * 255.0).round().clamp(0, 255);
    final int colorB = (color.b * 255.0).round().clamp(0, 255);
    final payload = PngEncoder.encodeCompactAlphaPngIsolateSafe(
      rawRgba: rawRgba,
      width: width,
      height: height,
      logicalWidth: logicalSize.width,
      logicalHeight: logicalSize.height,
      colorR: colorR,
      colorG: colorG,
      colorB: colorB,
      forceUniformColor: !preserveMultiColor,
    );
    if (payload == null) return null;
    return LatexRasterizerResult(
      bytes: payload.bytes,
      size: Size(payload.logicalWidth, payload.logicalHeight),
      offset: Offset(payload.offsetX, payload.offsetY),
    );
  }

  static Future<LatexRasterizerResult?> _encodeCompactLatexPngAsync({
    required Uint8List rawRgba,
    required int width,
    required int height,
    required Size logicalSize,
    required Color color,
    required bool preserveMultiColor,
  }) async {
    if (width * height < _isolatePixelThreshold) {
      return encodeCompactLatexPng(
        rawRgba: rawRgba,
        width: width,
        height: height,
        logicalSize: logicalSize,
        color: color,
        preserveMultiColor: preserveMultiColor,
      );
    }

    final int colorR = (color.r * 255.0).round().clamp(0, 255);
    final int colorG = (color.g * 255.0).round().clamp(0, 255);
    final int colorB = (color.b * 255.0).round().clamp(0, 255);
    final double logicalW = logicalSize.width;
    final double logicalH = logicalSize.height;
    final bool forceUniform = !preserveMultiColor;

    final payload = await Isolate.run(
      () => PngEncoder.encodeCompactAlphaPngIsolateSafe(
        rawRgba: rawRgba,
        width: width,
        height: height,
        logicalWidth: logicalW,
        logicalHeight: logicalH,
        colorR: colorR,
        colorG: colorG,
        colorB: colorB,
        forceUniformColor: forceUniform,
      ),
    );
    if (payload == null) return null;
    return LatexRasterizerResult(
      bytes: payload.bytes,
      size: Size(payload.logicalWidth, payload.logicalHeight),
      offset: Offset(payload.offsetX, payload.offsetY),
    );
  }

  static Future<LatexRasterizerResult?> rasterize({
    required String latex,
    required double fontSize,
    required Color color,
    double pixelRatio = 2.0,
  }) async {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return null;
      final view = views.first;

      final widget = MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Math.tex(
            latex,
            mathStyle: MathStyle.display,
            textScaleFactor: 1.0,
            textStyle: TextStyle(
              inherit: false,
              fontSize: fontSize,
              color: color,
            ),
            onErrorFallback: (err) => Text(
              latex,
              style: TextStyle(
                inherit: false,
                fontSize: fontSize,
                color: color,
              ),
            ),
          ),
        ),
      );

      final repaintBoundary = RenderRepaintBoundary();
      final renderView = RenderView(
        view: view,
        child: RenderPositionedBox(alignment: Alignment.center, child: repaintBoundary),
        configuration: ViewConfiguration(
          logicalConstraints: BoxConstraints.tight(const Size(4096, 4096)),
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

        final logicalSize = repaintBoundary.size;
        if (logicalSize.isEmpty) {
          return null;
        }

        final ui.Image image = await repaintBoundary.toImage(pixelRatio: pixelRatio);
        try {
          final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (byteData != null) {
            final rawBytes = Uint8List.fromList(
              byteData.buffer.asUint8List(
                byteData.offsetInBytes,
                byteData.lengthInBytes,
              ),
            );
            final hasColorCommand =
                latex.contains(r'\color') || latex.contains(r'\textcolor');
            return await _encodeCompactLatexPngAsync(
              rawRgba: rawBytes,
              width: image.width,
              height: image.height,
              logicalSize: logicalSize,
              color: color,
              preserveMultiColor: hasColorCommand,
            );
          }
        } finally {
          image.dispose();
        }
      } finally {
        if (rootElement != null) {
          try {
            buildOwner.buildScope(rootElement, () {
              RenderObjectToWidgetAdapter<RenderBox>(
                container: repaintBoundary,
              ).attachToRenderTree(buildOwner, rootElement);
            });
            buildOwner.finalizeTree();
          } catch (_) {}
        }
        pipelineOwner.rootNode = null;
        renderView.dispose();
        focusManager.dispose();
        pipelineOwner.dispose();
      }
    } catch (e) {
      debugPrint('LatexRasterizer.rasterize failed: $e');
    }
    return null;
  }
}

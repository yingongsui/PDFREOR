import 'dart:io' show ZLibCodec;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

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
  static const List<int> _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  static const List<int> _chunkIHDR = <int>[73, 72, 68, 82];
  static const List<int> _chunkIDAT = <int>[73, 68, 65, 84];
  static const List<int> _chunkIEND = <int>[73, 69, 78, 68];

  static final Uint32List _crcTable = _buildCrcTable();

  static Uint32List _buildCrcTable() {
    final table = Uint32List(256);
    for (int n = 0; n < 256; n++) {
      int c = n;
      for (int k = 0; k < 8; k++) {
        if ((c & 1) != 0) {
          c = 0xEDB88320 ^ (c >>> 1);
        } else {
          c = c >>> 1;
        }
      }
      table[n] = c;
    }
    return table;
  }

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
  /// and encodes a constant-color PNG (Grayscale+Alpha when monochrome, RGBA otherwise)
  /// so Syncfusion's PDF image stream compresses the color channel to near-zero bytes.
  static LatexRasterizerResult? encodeCompactLatexPng({
    required Uint8List rawRgba,
    required int width,
    required int height,
    required Size logicalSize,
    required Color color,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        logicalSize.width <= 0 ||
        logicalSize.height <= 0 ||
        rawRgba.length < width * height * 4) {
      return null;
    }

    int minX = width;
    int minY = height;
    int maxX = -1;
    int maxY = -1;

    final quantizedAlpha = Uint8List(width * height);
    for (int y = 0; y < height; y++) {
      final rowOffset = y * width;
      for (int x = 0; x < width; x++) {
        final pixelIdx = rowOffset + x;
        final rawA = rawRgba[(pixelIdx << 2) + 3];
        // Uniformly map 0..255 onto 16 steps (0, 17, 34, ..., 255)
        final qA = ((rawA + 8) ~/ 17) * 17;
        quantizedAlpha[pixelIdx] = qA;
        if (qA > 0) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (maxX < minX || maxY < minY) {
      return null;
    }

    // Preserve a 1px clamped transparent border to avoid bilinear UV edge clamping in PDF viewers
    final int cropLeft = math.max(0, minX - 1);
    final int cropTop = math.max(0, minY - 1);
    final int cropRight = math.min(width - 1, maxX + 1);
    final int cropBottom = math.min(height - 1, maxY + 1);
    final int cropW = cropRight - cropLeft + 1;
    final int cropH = cropBottom - cropTop + 1;

    final int colorR = (color.r * 255.0).round().clamp(0, 255);
    final int colorG = (color.g * 255.0).round().clamp(0, 255);
    final int colorB = (color.b * 255.0).round().clamp(0, 255);
    final bool isGrayscale = colorR == colorG && colorG == colorB;

    final int pngColorType;
    final Uint8List scanlines;

    if (isGrayscale) {
      // PNG Color Type 4: 8-bit Grayscale + 8-bit Alpha (DeviceGray + SMask in PDF)
      pngColorType = 4;
      final rowStride = 1 + cropW * 2;
      scanlines = Uint8List(cropH * rowStride);
      int dst = 0;
      for (int y = cropTop; y <= cropBottom; y++) {
        scanlines[dst++] = 0; // Filter type 0 (None)
        final srcRow = y * width;
        for (int x = cropLeft; x <= cropRight; x++) {
          scanlines[dst++] = colorR;
          scanlines[dst++] = quantizedAlpha[srcRow + x];
        }
      }
    } else {
      // PNG Color Type 6: 8-bit constant RGB + 8-bit Alpha (uniform DeviceRGB + SMask in PDF)
      pngColorType = 6;
      final rowStride = 1 + cropW * 4;
      scanlines = Uint8List(cropH * rowStride);
      int dst = 0;
      for (int y = cropTop; y <= cropBottom; y++) {
        scanlines[dst++] = 0; // Filter type 0 (None)
        final srcRow = y * width;
        for (int x = cropLeft; x <= cropRight; x++) {
          scanlines[dst++] = colorR;
          scanlines[dst++] = colorG;
          scanlines[dst++] = colorB;
          scanlines[dst++] = quantizedAlpha[srcRow + x];
        }
      }
    }

    final compressedIdat = ZLibCodec(level: 9).encode(scanlines);

    final ihdr = Uint8List(13);
    ihdr[0] = (cropW >>> 24) & 0xFF;
    ihdr[1] = (cropW >>> 16) & 0xFF;
    ihdr[2] = (cropW >>> 8) & 0xFF;
    ihdr[3] = cropW & 0xFF;
    ihdr[4] = (cropH >>> 24) & 0xFF;
    ihdr[5] = (cropH >>> 16) & 0xFF;
    ihdr[6] = (cropH >>> 8) & 0xFF;
    ihdr[7] = cropH & 0xFF;
    ihdr[8] = 8; // Bit depth
    ihdr[9] = pngColorType;
    ihdr[10] = 0; // Compression method (deflate)
    ihdr[11] = 0; // Filter method (adaptive)
    ihdr[12] = 0; // Interlace method (none)

    final out = BytesBuilder(copy: false);
    out.add(_pngSignature);
    _writePngChunk(out, _chunkIHDR, ihdr);
    _writePngChunk(out, _chunkIDAT, compressedIdat);
    _writePngChunk(out, _chunkIEND, const <int>[]);

    final scaleToLogicalX = logicalSize.width / width;
    final scaleToLogicalY = logicalSize.height / height;

    return LatexRasterizerResult(
      bytes: out.takeBytes(),
      size: Size(cropW * scaleToLogicalX, cropH * scaleToLogicalY),
      offset: Offset(cropLeft * scaleToLogicalX, cropTop * scaleToLogicalY),
    );
  }

  static void _writePngChunk(
    BytesBuilder out,
    List<int> chunkType,
    List<int> data,
  ) {
    final len = data.length;
    out.addByte((len >>> 24) & 0xFF);
    out.addByte((len >>> 16) & 0xFF);
    out.addByte((len >>> 8) & 0xFF);
    out.addByte(len & 0xFF);
    out.add(chunkType);
    if (len > 0) {
      out.add(data);
    }

    int crc = 0xFFFFFFFF;
    for (int i = 0; i < chunkType.length; i++) {
      crc = _crcTable[(crc ^ chunkType[i]) & 0xFF] ^ (crc >>> 8);
    }
    for (int i = 0; i < len; i++) {
      crc = _crcTable[(crc ^ data[i]) & 0xFF] ^ (crc >>> 8);
    }
    crc = (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;

    out.addByte((crc >>> 24) & 0xFF);
    out.addByte((crc >>> 16) & 0xFF);
    out.addByte((crc >>> 8) & 0xFF);
    out.addByte(crc & 0xFF);
  }

  static Future<LatexRasterizerResult?> rasterize({
    required String latex,
    required double fontSize,
    required Color color,
    double pixelRatio = 2.0,
  }) async {
    try {
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
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
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
            return encodeCompactLatexPng(
              rawRgba: byteData.buffer.asUint8List(
                byteData.offsetInBytes,
                byteData.lengthInBytes,
              ),
              width: image.width,
              height: image.height,
              logicalSize: logicalSize,
              color: color,
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
    } catch (_) {}
    return null;
  }
}

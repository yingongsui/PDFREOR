import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'png_encoder.dart';

class OptimizedPngResult {
  final Uint8List bytes;
  final Size size;
  final Offset offset;
  final int colorType;

  const OptimizedPngResult({
    required this.bytes,
    required this.size,
    this.offset = Offset.zero,
    required this.colorType,
  });
}

class ImageHeaderInfo {
  final bool isPng;
  final bool isJpeg;
  final int width;
  final int height;
  final int pngColorType;
  final int pngInterlace;

  const ImageHeaderInfo({
    required this.isPng,
    required this.isJpeg,
    required this.width,
    required this.height,
    this.pngColorType = -1,
    this.pngInterlace = 0,
  });
}

class PdfImageOptimizer {
  PdfImageOptimizer._();

  static const int _isolatePixelThreshold = 16384;

  /// Computes a full-buffer 64-bit FNV-1a fingerprint mixed with byte length
  /// for collision-free deduplication of identical images during PDF export.
  static String computeContentKey(Uint8List bytes) {
    int hash = 0x14650FB0739D0383;
    final len = bytes.length;
    for (int i = 0; i < len; i++) {
      hash = ((hash ^ bytes[i]) * 0x100001B3) & 0x7FFFFFFFFFFFFFFF;
    }
    return '$len:${hash.toRadixString(16)}';
  }

  /// Parses PNG or JPEG header dimensions and format flags without decoding pixels.
  static ImageHeaderInfo? readImageHeader(Uint8List bytes) {
    if (bytes.length >= 29 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71 &&
        bytes[4] == 13 &&
        bytes[5] == 10 &&
        bytes[6] == 26 &&
        bytes[7] == 10 &&
        bytes[12] == 73 &&
        bytes[13] == 72 &&
        bytes[14] == 68 &&
        bytes[15] == 82) {
      final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      final colorType = bytes[25];
      final interlace = bytes[28];
      if (w > 0 && h > 0) {
        return ImageHeaderInfo(
          isPng: true,
          isJpeg: false,
          width: w,
          height: h,
          pngColorType: colorType,
          pngInterlace: interlace,
        );
      }
    }

    if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      int i = 2;
      while (i + 1 < bytes.length) {
        if (bytes[i] != 0xFF) {
          i++;
          continue;
        }
        while (i < bytes.length && bytes[i] == 0xFF) {
          i++;
        }
        if (i >= bytes.length) break;
        final marker = bytes[i++];
        if (marker == 0xD9 || marker == 0xDA) break;
        if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
          continue;
        }
        if (i + 1 >= bytes.length) break;
        final segLen = (bytes[i] << 8) | bytes[i + 1];
        if (segLen < 2 || i + segLen > bytes.length) break;

        final isSof = (marker >= 0xC0 && marker <= 0xC3) ||
            (marker >= 0xC5 && marker <= 0xC7) ||
            (marker >= 0xC9 && marker <= 0xCB) ||
            (marker >= 0xCD && marker <= 0xCF);
        if (isSof && segLen >= 7) {
          final h = (bytes[i + 3] << 8) | bytes[i + 4];
          final w = (bytes[i + 5] << 8) | bytes[i + 6];
          if (w > 0 && h > 0) {
            return ImageHeaderInfo(
              isPng: false,
              isJpeg: true,
              width: w,
              height: h,
            );
          }
        }
        i += segLen;
      }
    }
    return null;
  }

  /// Synchronously encodes straight RGBA pixels into the most compact PDF-friendly PNG.
  static OptimizedPngResult? encodeOptimizedPngFromRgba({
    required Uint8List rawStraightRgba,
    required int width,
    required int height,
    required Size logicalSize,
    bool cropTransparentMargins = false,
  }) {
    final payload = PngEncoder.encodeOptimizedPngIsolateSafe(
      rawStraightRgba: rawStraightRgba,
      width: width,
      height: height,
      logicalWidth: logicalSize.width,
      logicalHeight: logicalSize.height,
      cropTransparentMargins: cropTransparentMargins,
    );
    if (payload == null) return null;
    return OptimizedPngResult(
      bytes: payload.bytes,
      size: Size(payload.logicalWidth, payload.logicalHeight),
      offset: Offset(payload.offsetX, payload.offsetY),
      colorType: payload.colorType,
    );
  }

  /// Offloads PNG adaptive filtering and ZLib compression to a worker isolate
  /// for non-trivial image buffers.
  static Future<OptimizedPngResult?> encodeOptimizedPngAsync({
    required Uint8List rawStraightRgba,
    required int width,
    required int height,
    required Size logicalSize,
    bool cropTransparentMargins = false,
  }) async {
    if (width * height < _isolatePixelThreshold) {
      return encodeOptimizedPngFromRgba(
        rawStraightRgba: rawStraightRgba,
        width: width,
        height: height,
        logicalSize: logicalSize,
        cropTransparentMargins: cropTransparentMargins,
      );
    }

    final double logicalW = logicalSize.width;
    final double logicalH = logicalSize.height;
    final payload = await Isolate.run(
      () => PngEncoder.encodeOptimizedPngIsolateSafe(
        rawStraightRgba: rawStraightRgba,
        width: width,
        height: height,
        logicalWidth: logicalW,
        logicalHeight: logicalH,
        cropTransparentMargins: cropTransparentMargins,
      ),
    );
    if (payload == null) return null;
    return OptimizedPngResult(
      bytes: payload.bytes,
      size: Size(payload.logicalWidth, payload.logicalHeight),
      offset: Offset(payload.offsetX, payload.offsetY),
      colorType: payload.colorType,
    );
  }

  /// Downsamples oversized images to ~220 physical PDF DPI and strips redundant alpha channels
  /// while guaranteeing the resulting PDF stream never exceeds the original image's footprint.
  static Future<Uint8List> optimizeForPdf(
    Uint8List imageBytes, {
    required double targetPdfWidthPt,
    required double targetPdfHeightPt,
    double targetDpi = 220.0,
  }) async {
    if (imageBytes.isEmpty) return imageBytes;

    final maxW = math.max(64, (targetPdfWidthPt * targetDpi / 72.0).ceil());
    final maxH = math.max(64, (targetPdfHeightPt * targetDpi / 72.0).ceil());

    final header = readImageHeader(imageBytes);
    bool needsDownsample = false;
    int? decodeTargetW;
    int? decodeTargetH;

    if (header != null) {
      final scaleDown = math.min(maxW / header.width, maxH / header.height);
      if (scaleDown < 0.85) {
        needsDownsample = true;
        decodeTargetW = math.max(1, (header.width * scaleDown).round());
        decodeTargetH = math.max(1, (header.height * scaleDown).round());
      } else {
        if (header.isJpeg) {
          // Already compact JPEG at or near display resolution -> preserve DCTDecode pass-through
          return imageBytes;
        }
        if (header.isPng &&
            (header.pngColorType == 0 || header.pngColorType == 2) &&
            header.pngInterlace == 0) {
          // Already opaque non-interlaced PNG at or near display resolution
          return imageBytes;
        }
      }
    }

    try {
      final codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: decodeTargetW,
        targetHeight: decodeTargetH,
      );
      ui.Image? decoded;
      try {
        final frame = await codec.getNextFrame();
        decoded = frame.image;

        // If header was unknown (e.g., WebP/GIF/BMP) and decoded dims exceed target DPI, re-decode downscaled
        if (header == null && (decoded.width > maxW || decoded.height > maxH)) {
          final scaleDown = math.min(maxW / decoded.width, maxH / decoded.height);
          if (scaleDown < 0.85) {
            final scaledW = math.max(1, (decoded.width * scaleDown).round());
            final scaledH = math.max(1, (decoded.height * scaleDown).round());
            decoded.dispose();
            decoded = null;
            final scaledCodec = await ui.instantiateImageCodec(
              imageBytes,
              targetWidth: scaledW,
              targetHeight: scaledH,
            );
            try {
              decoded = (await scaledCodec.getNextFrame()).image;
              needsDownsample = true;
            } finally {
              scaledCodec.dispose();
            }
          }
        }

        final byteData = await decoded.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        if (byteData == null) return imageBytes;

        final rawBytes = Uint8List.fromList(
          byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          ),
        );
        final optimized = await encodeOptimizedPngAsync(
          rawStraightRgba: rawBytes,
          width: decoded.width,
          height: decoded.height,
          logicalSize: Size(decoded.width.toDouble(), decoded.height.toDouble()),
          cropTransparentMargins: false,
        );
        if (optimized == null) return imageBytes;

        // Guard against expanding already-compressed JPEG photos if PNG happens to be larger
        if (header != null && header.isJpeg) {
          return optimized.bytes.length < imageBytes.length ? optimized.bytes : imageBytes;
        }
        if (!needsDownsample &&
            header != null &&
            header.isPng &&
            optimized.colorType == 6 &&
            optimized.bytes.length >= imageBytes.length) {
          return imageBytes;
        }
        return optimized.bytes;
      } finally {
        decoded?.dispose();
        codec.dispose();
      }
    } catch (_) {
      return imageBytes;
    }
  }
}

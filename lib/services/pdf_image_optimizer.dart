import 'dart:io' show ZLibCodec;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'latex_rasterizer.dart';

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

  /// Computes a fast 64-bit content fingerprint mixed with byte length
  /// for deduplicating identical images during PDF export.
  static String computeContentKey(Uint8List bytes) {
    int hash = 0x14650FB0739D0383;
    final len = bytes.length;
    // Sample all bytes when <= 64 KB, or strided across the whole buffer when larger
    final int step = len <= 65536 ? 1 : (len ~/ 32768);
    for (int i = 0; i < len; i += step) {
      hash = ((hash ^ bytes[i]) * 0x100001B3) & 0x7FFFFFFFFFFFFFFF;
    }
    if (len > 0) {
      hash = ((hash ^ bytes[len - 1]) * 0x100001B3) & 0x7FFFFFFFFFFFFFFF;
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

  /// Encodes straight RGBA pixels into the most compact PDF-friendly PNG representation:
  /// - Fully opaque grayscale -> PNG colorType 0 with adaptive Sub/Up/Paeth filtering (no SMask)
  /// - Fully opaque RGB -> PNG colorType 2 with adaptive Sub/Up/Paeth filtering (no SMask)
  /// - Transparent single-color -> constant-color PNG via LatexRasterizer
  /// - Transparent multi-color -> PNG colorType 6 with zeroed transparent RGB & quantized alpha
  static OptimizedPngResult? encodeOptimizedPngFromRgba({
    required Uint8List rawStraightRgba,
    required int width,
    required int height,
    required Size logicalSize,
    bool cropTransparentMargins = false,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        logicalSize.width <= 0 ||
        logicalSize.height <= 0 ||
        rawStraightRgba.length < width * height * 4) {
      return null;
    }

    bool hasTransparency = false;
    bool isGrayscale = true;
    bool isSingleSolidColor = true;
    int firstR = -1;
    int firstG = -1;
    int firstB = -1;

    int minX = width;
    int minY = height;
    int maxX = -1;
    int maxY = -1;

    for (int y = 0; y < height; y++) {
      final rowOffset = y * width;
      for (int x = 0; x < width; x++) {
        final idx = (rowOffset + x) << 2;
        final a = rawStraightRgba[idx + 3];
        if (a < 252) {
          hasTransparency = true;
        }
        if (a > 4) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;

          final r = rawStraightRgba[idx];
          final g = rawStraightRgba[idx + 1];
          final b = rawStraightRgba[idx + 2];
          if (r != g || g != b) {
            isGrayscale = false;
          }
          if (firstR < 0) {
            firstR = r;
            firstG = g;
            firstB = b;
          } else if (isSingleSolidColor &&
              ((r - firstR).abs() > 2 || (g - firstG).abs() > 2 || (b - firstB).abs() > 2)) {
            isSingleSolidColor = false;
          }
        }
      }
    }

    if (maxX < minX || maxY < minY) {
      return null;
    }

    if (cropTransparentMargins && hasTransparency && isSingleSolidColor && firstR >= 0) {
      final compact = LatexRasterizer.encodeCompactLatexPng(
        rawRgba: rawStraightRgba,
        width: width,
        height: height,
        logicalSize: logicalSize,
        color: Color.fromARGB(255, firstR, firstG, firstB),
      );
      if (compact == null) return null;
      return OptimizedPngResult(
        bytes: compact.bytes,
        size: compact.size,
        offset: compact.offset,
        colorType: isGrayscale ? 4 : 6,
      );
    }

    final int cropLeft = (cropTransparentMargins && hasTransparency) ? math.max(0, minX - 1) : 0;
    final int cropTop = (cropTransparentMargins && hasTransparency) ? math.max(0, minY - 1) : 0;
    final int cropRight =
        (cropTransparentMargins && hasTransparency) ? math.min(width - 1, maxX + 1) : (width - 1);
    final int cropBottom =
        (cropTransparentMargins && hasTransparency) ? math.min(height - 1, maxY + 1) : (height - 1);
    final int cropW = cropRight - cropLeft + 1;
    final int cropH = cropBottom - cropTop + 1;

    int pngColorType;
    Uint8List scanlines;

    if (!hasTransparency) {
      // Opaque image: Syncfusion passes IDAT directly into PDF with Predictor 15 and NO SMask!
      final int bpp = isGrayscale ? 1 : 3;
      pngColorType = isGrayscale ? 0 : 2;
      final int rowByteLen = cropW * bpp;
      scanlines = _encodeAdaptiveFilteredScanlines(
        rawStraightRgba: rawStraightRgba,
        srcWidth: width,
        cropLeft: cropLeft,
        cropTop: cropTop,
        cropW: cropW,
        cropH: cropH,
        bpp: bpp,
        rowByteLen: rowByteLen,
      );
    } else {
      // Multi-color image with alpha: zero out RGB on transparent pixels & quantize alpha to 32 steps
      pngColorType = 6;
      final rowStride = 1 + cropW * 4;
      scanlines = Uint8List(cropH * rowStride);
      int dst = 0;
      for (int y = cropTop; y <= cropBottom; y++) {
        scanlines[dst++] = 0; // Filter 0 (Syncfusion decodes colorType 6)
        final srcRow = y * width;
        for (int x = cropLeft; x <= cropRight; x++) {
          final idx = (srcRow + x) << 2;
          final rawA = rawStraightRgba[idx + 3];
          final int qA = rawA <= 4
              ? 0
              : (rawA >= 251 ? 255 : ((rawA + 4) ~/ 8) * 8);
          if (qA == 0) {
            scanlines[dst++] = 0;
            scanlines[dst++] = 0;
            scanlines[dst++] = 0;
            scanlines[dst++] = 0;
          } else {
            scanlines[dst++] = rawStraightRgba[idx];
            scanlines[dst++] = rawStraightRgba[idx + 1];
            scanlines[dst++] = rawStraightRgba[idx + 2];
            scanlines[dst++] = qA;
          }
        }
      }
    }

    final compressedIdat = ZLibCodec(level: 9).encode(scanlines);
    final pngBytes = _wrapPng(cropW, cropH, pngColorType, compressedIdat);

    final scaleToLogicalX = logicalSize.width / width;
    final scaleToLogicalY = logicalSize.height / height;

    return OptimizedPngResult(
      bytes: pngBytes,
      size: Size(cropW * scaleToLogicalX, cropH * scaleToLogicalY),
      offset: Offset(cropLeft * scaleToLogicalX, cropTop * scaleToLogicalY),
      colorType: pngColorType,
    );
  }

  static Uint8List _encodeAdaptiveFilteredScanlines({
    required Uint8List rawStraightRgba,
    required int srcWidth,
    required int cropLeft,
    required int cropTop,
    required int cropW,
    required int cropH,
    required int bpp,
    required int rowByteLen,
  }) {
    final out = Uint8List(cropH * (1 + rowByteLen));
    Uint8List prevRow = Uint8List(rowByteLen);
    Uint8List currRow = Uint8List(rowByteLen);

    final subBuf = Uint8List(rowByteLen);
    final upBuf = Uint8List(rowByteLen);
    final paethBuf = Uint8List(rowByteLen);

    int dstOffset = 0;
    for (int r = 0; r < cropH; r++) {
      final srcY = cropTop + r;
      final srcRowBase = srcY * srcWidth;
      int p = 0;
      if (bpp == 1) {
        for (int c = 0; c < cropW; c++) {
          currRow[p++] = rawStraightRgba[(srcRowBase + cropLeft + c) << 2];
        }
      } else {
        for (int c = 0; c < cropW; c++) {
          final idx = (srcRowBase + cropLeft + c) << 2;
          currRow[p++] = rawStraightRgba[idx];
          currRow[p++] = rawStraightRgba[idx + 1];
          currRow[p++] = rawStraightRgba[idx + 2];
        }
      }

      int scoreNone = 0;
      int scoreSub = 0;
      int scoreUp = 0;
      int scorePaeth = 0;

      for (int i = 0; i < rowByteLen; i++) {
        final raw = currRow[i];
        scoreNone += raw < 128 ? raw : (256 - raw);

        final a = i >= bpp ? currRow[i - bpp] : 0;
        final b = prevRow[i];
        final c = i >= bpp ? prevRow[i - bpp] : 0;

        final subVal = (raw - a) & 0xFF;
        subBuf[i] = subVal;
        scoreSub += subVal < 128 ? subVal : (256 - subVal);

        final upVal = (raw - b) & 0xFF;
        upBuf[i] = upVal;
        scoreUp += upVal < 128 ? upVal : (256 - upVal);

        final pred = a + b - c;
        final pa = (pred - a).abs();
        final pb = (pred - b).abs();
        final pc = (pred - c).abs();
        final pr = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
        final paethVal = (raw - pr) & 0xFF;
        paethBuf[i] = paethVal;
        scorePaeth += paethVal < 128 ? paethVal : (256 - paethVal);
      }

      int bestFilter = 4;
      Uint8List bestBuf = paethBuf;
      int bestScore = scorePaeth;

      if (scoreSub < bestScore) {
        bestScore = scoreSub;
        bestFilter = 1;
        bestBuf = subBuf;
      }
      if (scoreUp < bestScore) {
        bestScore = scoreUp;
        bestFilter = 2;
        bestBuf = upBuf;
      }
      if (scoreNone < bestScore) {
        bestFilter = 0;
        bestBuf = currRow;
      }

      out[dstOffset++] = bestFilter;
      out.setRange(dstOffset, dstOffset + rowByteLen, bestBuf);
      dstOffset += rowByteLen;

      final tmp = prevRow;
      prevRow = currRow;
      currRow = tmp;
    }

    return out;
  }

  static Uint8List _wrapPng(int width, int height, int colorType, List<int> compressedIdat) {
    final ihdr = Uint8List(13);
    ihdr[0] = (width >>> 24) & 0xFF;
    ihdr[1] = (width >>> 16) & 0xFF;
    ihdr[2] = (width >>> 8) & 0xFF;
    ihdr[3] = width & 0xFF;
    ihdr[4] = (height >>> 24) & 0xFF;
    ihdr[5] = (height >>> 16) & 0xFF;
    ihdr[6] = (height >>> 8) & 0xFF;
    ihdr[7] = height & 0xFF;
    ihdr[8] = 8;
    ihdr[9] = colorType;
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;

    final out = BytesBuilder(copy: false);
    out.add(_pngSignature);
    _writePngChunk(out, _chunkIHDR, ihdr);
    _writePngChunk(out, _chunkIDAT, compressedIdat);
    _writePngChunk(out, _chunkIEND, const <int>[]);
    return out.takeBytes();
  }

  static void _writePngChunk(BytesBuilder out, List<int> chunkType, List<int> data) {
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
        final byteData = await decoded.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        if (byteData == null) return imageBytes;

        final optimized = encodeOptimizedPngFromRgba(
          rawStraightRgba: byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          ),
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

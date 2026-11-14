import 'dart:io' show ZLibCodec;
import 'dart:math' as math;
import 'dart:typed_data';

class EncodedPngPayload {
  final Uint8List bytes;
  final double logicalWidth;
  final double logicalHeight;
  final double offsetX;
  final double offsetY;
  final int colorType;

  const EncodedPngPayload({
    required this.bytes,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.offsetX,
    required this.offsetY,
    required this.colorType,
  });
}

class PngEncoder {
  PngEncoder._();

  static const List<int> pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  static const List<int> chunkIHDR = <int>[73, 72, 68, 82];
  static const List<int> chunkIDAT = <int>[73, 68, 65, 84];
  static const List<int> chunkIEND = <int>[73, 69, 78, 68];

  static final Uint32List _crcTable = _buildCrcTable();

  static Uint32List _buildCrcTable() {
    final table = Uint32List(256);
    for (int n = 0; n < 256; n++) {
      int c = n;
      for (int k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[n] = c;
    }
    return table;
  }

  static Uint8List wrapPng(
    int width,
    int height,
    int colorType,
    List<int> compressedIdat,
  ) {
    final ihdr = Uint8List(13);
    ihdr[0] = (width >>> 24) & 0xFF;
    ihdr[1] = (width >>> 16) & 0xFF;
    ihdr[2] = (width >>> 8) & 0xFF;
    ihdr[3] = width & 0xFF;
    ihdr[4] = (height >>> 24) & 0xFF;
    ihdr[5] = (height >>> 16) & 0xFF;
    ihdr[6] = (height >>> 8) & 0xFF;
    ihdr[7] = height & 0xFF;
    ihdr[8] = 8; // Bit depth
    ihdr[9] = colorType;
    ihdr[10] = 0; // Compression method (deflate)
    ihdr[11] = 0; // Filter method (adaptive)
    ihdr[12] = 0; // Interlace method (none)

    final out = BytesBuilder(copy: false);
    out.add(pngSignature);
    writePngChunk(out, chunkIHDR, ihdr);
    writePngChunk(out, chunkIDAT, compressedIdat);
    writePngChunk(out, chunkIEND, const <int>[]);
    return out.takeBytes();
  }

  static void writePngChunk(
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

  /// Crops transparent margins, quantizes alpha to 16 clean levels, and encodes
  /// a compact PNG. Uses uniform [colorR]/[colorG]/[colorB] (colorType 4 or 6)
  /// for single-color foregrounds, or preserves RGB channels if multi-colored.
  static EncodedPngPayload? encodeCompactAlphaPngIsolateSafe({
    required Uint8List rawRgba,
    required int width,
    required int height,
    required double logicalWidth,
    required double logicalHeight,
    required int colorR,
    required int colorG,
    required int colorB,
    bool forceUniformColor = false,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        logicalWidth <= 0 ||
        logicalHeight <= 0 ||
        rawRgba.length < width * height * 4) {
      return null;
    }

    int minX = width;
    int minY = height;
    int maxX = -1;
    int maxY = -1;
    bool isUniformColor = true;
    bool isGrayscale = colorR == colorG && colorG == colorB;

    // Pass 1: locate tight non-transparent bounding box & detect multi-color spans
    for (int y = 0; y < height; y++) {
      final rowOffset = y * width;
      for (int x = 0; x < width; x++) {
        final idx = (rowOffset + x) << 2;
        final rawA = rawRgba[idx + 3];
        final qA = ((rawA + 8) ~/ 17) * 17;
        if (qA > 0) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;

          if (!forceUniformColor && rawA >= 200) {
            final r = rawRgba[idx];
            final g = rawRgba[idx + 1];
            final b = rawRgba[idx + 2];
            if (isGrayscale && (r != g || g != b)) {
              isGrayscale = false;
            }
            if (isUniformColor &&
                ((r - colorR).abs() > 6 ||
                    (g - colorG).abs() > 6 ||
                    (b - colorB).abs() > 6)) {
              isUniformColor = false;
            }
          }
        }
      }
    }

    if (maxX < minX || maxY < minY) {
      return null;
    }

    // Preserve a 1px clamped transparent border to avoid bilinear UV edge clamping
    final int cropLeft = math.max(0, minX - 1);
    final int cropTop = math.max(0, minY - 1);
    final int cropRight = math.min(width - 1, maxX + 1);
    final int cropBottom = math.min(height - 1, maxY + 1);
    final int cropW = cropRight - cropLeft + 1;
    final int cropH = cropBottom - cropTop + 1;

    final int pngColorType;
    final Uint8List scanlines;

    if (forceUniformColor || isUniformColor) {
      if (isGrayscale) {
        pngColorType = 4;
        final rowStride = 1 + cropW * 2;
        scanlines = Uint8List(cropH * rowStride);
        int dst = 0;
        for (int y = cropTop; y <= cropBottom; y++) {
          scanlines[dst++] = 0;
          final srcRow = y * width;
          for (int x = cropLeft; x <= cropRight; x++) {
            final rawA = rawRgba[((srcRow + x) << 2) + 3];
            scanlines[dst++] = colorR;
            scanlines[dst++] = ((rawA + 8) ~/ 17) * 17;
          }
        }
      } else {
        pngColorType = 6;
        final rowStride = 1 + cropW * 4;
        scanlines = Uint8List(cropH * rowStride);
        int dst = 0;
        for (int y = cropTop; y <= cropBottom; y++) {
          scanlines[dst++] = 0;
          final srcRow = y * width;
          for (int x = cropLeft; x <= cropRight; x++) {
            final rawA = rawRgba[((srcRow + x) << 2) + 3];
            scanlines[dst++] = colorR;
            scanlines[dst++] = colorG;
            scanlines[dst++] = colorB;
            scanlines[dst++] = ((rawA + 8) ~/ 17) * 17;
          }
        }
      }
    } else {
      pngColorType = 6;
      final rowStride = 1 + cropW * 4;
      scanlines = Uint8List(cropH * rowStride);
      int dst = 0;
      for (int y = cropTop; y <= cropBottom; y++) {
        scanlines[dst++] = 0;
        final srcRow = y * width;
        for (int x = cropLeft; x <= cropRight; x++) {
          final idx = (srcRow + x) << 2;
          final rawA = rawRgba[idx + 3];
          final qA = ((rawA + 8) ~/ 17) * 17;
          if (qA == 0) {
            scanlines[dst++] = 0;
            scanlines[dst++] = 0;
            scanlines[dst++] = 0;
            scanlines[dst++] = 0;
          } else {
            scanlines[dst++] = rawRgba[idx];
            scanlines[dst++] = rawRgba[idx + 1];
            scanlines[dst++] = rawRgba[idx + 2];
            scanlines[dst++] = qA;
          }
        }
      }
    }

    final compressedIdat = ZLibCodec(level: 9).encode(scanlines);
    final pngBytes = wrapPng(cropW, cropH, pngColorType, compressedIdat);

    final scaleToLogicalX = logicalWidth / width;
    final scaleToLogicalY = logicalHeight / height;

    return EncodedPngPayload(
      bytes: pngBytes,
      logicalWidth: cropW * scaleToLogicalX,
      logicalHeight: cropH * scaleToLogicalY,
      offsetX: cropLeft * scaleToLogicalX,
      offsetY: cropTop * scaleToLogicalY,
      colorType: pngColorType,
    );
  }

  /// Pure-Dart PNG optimizer (isolate-safe) for straight RGBA pixels.
  static EncodedPngPayload? encodeOptimizedPngIsolateSafe({
    required Uint8List rawStraightRgba,
    required int width,
    required int height,
    required double logicalWidth,
    required double logicalHeight,
    bool cropTransparentMargins = false,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        logicalWidth <= 0 ||
        logicalHeight <= 0 ||
        rawStraightRgba.length < width * height * 4) {
      return null;
    }

    bool hasTransparency = false;
    bool isGrayscale = true;
    bool isSingleSolidColor = true;
    int sampleR = -1;
    int sampleG = -1;
    int sampleB = -1;
    int sampleMaxAlpha = -1;

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
          if (sampleR < 0) {
            sampleR = r;
            sampleG = g;
            sampleB = b;
            sampleMaxAlpha = a;
          } else {
            if (a > sampleMaxAlpha) {
              sampleR = r;
              sampleG = g;
              sampleB = b;
              sampleMaxAlpha = a;
            }
            if (isSingleSolidColor &&
                a >= 180 &&
                ((r - sampleR).abs() > 3 ||
                    (g - sampleG).abs() > 3 ||
                    (b - sampleB).abs() > 3)) {
              isSingleSolidColor = false;
            }
          }
        }
      }
    }

    if (maxX < minX || maxY < minY) {
      return null;
    }

    if (cropTransparentMargins &&
        hasTransparency &&
        isSingleSolidColor &&
        sampleR >= 0) {
      return encodeCompactAlphaPngIsolateSafe(
        rawRgba: rawStraightRgba,
        width: width,
        height: height,
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        colorR: sampleR,
        colorG: sampleG,
        colorB: sampleB,
        forceUniformColor: true,
      );
    }

    final int cropLeft =
        (cropTransparentMargins && hasTransparency) ? math.max(0, minX - 1) : 0;
    final int cropTop =
        (cropTransparentMargins && hasTransparency) ? math.max(0, minY - 1) : 0;
    final int cropRight = (cropTransparentMargins && hasTransparency)
        ? math.min(width - 1, maxX + 1)
        : (width - 1);
    final int cropBottom = (cropTransparentMargins && hasTransparency)
        ? math.min(height - 1, maxY + 1)
        : (height - 1);
    final int cropW = cropRight - cropLeft + 1;
    final int cropH = cropBottom - cropTop + 1;

    final int pngColorType;
    final Uint8List scanlines;

    if (!hasTransparency) {
      final int bpp = isGrayscale ? 1 : 3;
      pngColorType = isGrayscale ? 0 : 2;
      final int rowByteLen = cropW * bpp;
      scanlines = encodeAdaptiveFilteredScanlines(
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
      pngColorType = 6;
      final rowStride = 1 + cropW * 4;
      scanlines = Uint8List(cropH * rowStride);
      int dst = 0;
      for (int y = cropTop; y <= cropBottom; y++) {
        scanlines[dst++] = 0;
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
    final pngBytes = wrapPng(cropW, cropH, pngColorType, compressedIdat);

    final scaleToLogicalX = logicalWidth / width;
    final scaleToLogicalY = logicalHeight / height;

    return EncodedPngPayload(
      bytes: pngBytes,
      logicalWidth: cropW * scaleToLogicalX,
      logicalHeight: cropH * scaleToLogicalY,
      offsetX: cropLeft * scaleToLogicalX,
      offsetY: cropTop * scaleToLogicalY,
      colorType: pngColorType,
    );
  }

  static Uint8List encodeAdaptiveFilteredScanlines({
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
}

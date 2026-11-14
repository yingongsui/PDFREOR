import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../editor_settings_service.dart';

final RegExp _jpKanaRegex = RegExp(r'[\u3040-\u30ff]');
final RegExp _krHangulRegex = RegExp(r'[\uac00-\ud7af]');
final RegExp _cjkIdeographRegex = RegExp(
  r'[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff\u3000-\u303f\uff00-\uffef]',
);

// WinAnsi (Windows-1252) extras in U+0100..U+2122 range supported by PdfStandardFont
const Set<int> _winAnsiExtras = <int>{
  0x20AC, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6,
  0x2030, 0x0160, 0x2039, 0x0152, 0x017D, 0x2018, 0x2019, 0x201C,
  0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A,
  0x0153, 0x017E, 0x0178,
};

bool isWinAnsiText(String text) {
  for (final code in text.codeUnits) {
    if ((code >= 32 && code <= 126) ||
        code == 10 ||
        code == 13 ||
        code == 9 ||
        (code >= 160 && code <= 255) ||
        _winAnsiExtras.contains(code)) {
      continue;
    }
    return false;
  }
  return true;
}

String resolveExportFontCategory(String text, AppFontFamily textBoxFont) {
  if (_jpKanaRegex.hasMatch(text)) {
    return textBoxFont == AppFontFamily.serif ? 'jp_serif' : 'jp_sans';
  }
  if (_krHangulRegex.hasMatch(text)) {
    return textBoxFont == AppFontFamily.serif ? 'kr_serif' : 'kr_sans';
  }
  if (!_cjkIdeographRegex.hasMatch(text) && isWinAnsiText(text)) {
    return 'ascii_${textBoxFont.name}';
  }
  return 'cjk_song';
}

sf.PdfFont createPdfFontForCategory(String fontCategory, double pdfFontSize) {
  switch (fontCategory) {
    case 'ascii_sansSerif':
      return sf.PdfStandardFont(sf.PdfFontFamily.helvetica, pdfFontSize);
    case 'ascii_serif':
      return sf.PdfStandardFont(sf.PdfFontFamily.timesRoman, pdfFontSize);
    case 'ascii_monospace':
      return sf.PdfStandardFont(sf.PdfFontFamily.courier, pdfFontSize);
    case 'jp_serif':
      return sf.PdfCjkStandardFont(
        sf.PdfCjkFontFamily.heiseiMinchoW3,
        pdfFontSize,
      );
    case 'jp_sans':
      return sf.PdfCjkStandardFont(
        sf.PdfCjkFontFamily.heiseiKakuGothicW5,
        pdfFontSize,
      );
    case 'kr_serif':
      return sf.PdfCjkStandardFont(
        sf.PdfCjkFontFamily.hanyangSystemsShinMyeongJoMedium,
        pdfFontSize,
      );
    case 'kr_sans':
      return sf.PdfCjkStandardFont(
        sf.PdfCjkFontFamily.hanyangSystemsGothicMedium,
        pdfFontSize,
      );
    default:
      return sf.PdfCjkStandardFont(
        sf.PdfCjkFontFamily.sinoTypeSongLight,
        pdfFontSize,
      );
  }
}

sf.PdfColor toPdfColor(int argb) {
  return sf.PdfColor(
    (argb >>> 16) & 0xFF,
    (argb >>> 8) & 0xFF,
    argb & 0xFF,
    (argb >>> 24) & 0xFF,
  );
}

/// Quantizes a PDF point coordinate to 0.1 pt (1/720 inch) precision to reduce
/// floating-point string bloat and improve Deflate compression of content streams.
double roundPdfCoord(double value) {
  return (value * 10.0).roundToDouble() / 10.0;
}

Offset roundPdfOffset(Offset p) {
  return Offset(roundPdfCoord(p.dx), roundPdfCoord(p.dy));
}

Rect roundPdfRect(Rect r) {
  final left = roundPdfCoord(r.left);
  final top = roundPdfCoord(r.top);
  final right = roundPdfCoord(r.right);
  final bottom = roundPdfCoord(r.bottom);
  return Rect.fromLTRB(left, top, math.max(left, right), math.max(top, bottom));
}

/// Simplifies a polyline in PDF point space using iterative Ramer-Douglas-Peucker (RDP)
/// and quantizes surviving vertices to 0.1 pt precision.
List<Offset> simplifyStrokePoints(
  List<Offset> points, {
  double epsilon = 0.25,
}) {
  if (points.isEmpty) return const <Offset>[];
  if (points.length == 1) return <Offset>[roundPdfOffset(points.first)];
  if (points.length == 2) {
    final p0 = roundPdfOffset(points.first);
    final p1 = roundPdfOffset(points.last);
    return p0 == p1 ? <Offset>[p0] : <Offset>[p0, p1];
  }

  final int n = points.length;
  final keep = Uint8List(n);
  keep[0] = 1;
  keep[n - 1] = 1;

  final double epsSq = epsilon * epsilon;
  final List<int> stack = <int>[0, n - 1];

  while (stack.isNotEmpty) {
    final int endIdx = stack.removeLast();
    final int startIdx = stack.removeLast();
    if (endIdx - startIdx <= 1) continue;

    final double ax = points[startIdx].dx;
    final double ay = points[startIdx].dy;
    final double bx = points[endIdx].dx;
    final double by = points[endIdx].dy;
    final double dx = bx - ax;
    final double dy = by - ay;
    final double lenSq = dx * dx + dy * dy;

    double maxDistSq = -1.0;
    int maxIdx = -1;

    for (int i = startIdx + 1; i < endIdx; i++) {
      final double px = points[i].dx;
      final double py = points[i].dy;
      double distSq;
      if (lenSq < 1e-9) {
        final double ex = px - ax;
        final double ey = py - ay;
        distSq = ex * ex + ey * ey;
      } else {
        final double t = (((px - ax) * dx + (py - ay) * dy) / lenSq).clamp(0.0, 1.0);
        final double projX = ax + t * dx;
        final double projY = ay + t * dy;
        final double ex = px - projX;
        final double ey = py - projY;
        distSq = ex * ex + ey * ey;
      }
      if (distSq > maxDistSq) {
        maxDistSq = distSq;
        maxIdx = i;
      }
    }

    if (maxDistSq > epsSq && maxIdx != -1) {
      keep[maxIdx] = 1;
      stack.add(startIdx);
      stack.add(maxIdx);
      stack.add(maxIdx);
      stack.add(endIdx);
    }
  }

  final List<Offset> result = <Offset>[];
  Offset? prev;
  for (int i = 0; i < n; i++) {
    if (keep[i] == 1) {
      final q = roundPdfOffset(points[i]);
      if (prev == null || q != prev) {
        result.add(q);
        prev = q;
      }
    }
  }
  if (result.isEmpty) {
    result.add(roundPdfOffset(points.first));
  }
  return result;
}

/// Merges collinear horizontally adjacent or overlapping selection rectangles
/// on the same text line into single span rectangles, reducing draw ops and avoiding
/// dark multiply-blend seams between adjacent highlight boxes.
List<Rect> mergeCollinearRects(List<Rect> rects) {
  final valid = rects.where((r) => r.width > 0 && r.height > 0).toList();
  if (valid.isEmpty) return const <Rect>[];
  if (valid.length == 1) return <Rect>[roundPdfRect(valid.first)];

  valid.sort((a, b) => a.center.dy.compareTo(b.center.dy));

  final List<List<Rect>> lineBands = <List<Rect>>[];
  for (final r in valid) {
    if (lineBands.isEmpty) {
      lineBands.add(<Rect>[r]);
    } else {
      final currentBand = lineBands.last;
      final bandRef = currentBand.first;
      final tolY = math.min(r.height, bandRef.height) * 0.45;
      if ((r.center.dy - bandRef.center.dy).abs() <= tolY) {
        currentBand.add(r);
      } else {
        lineBands.add(<Rect>[r]);
      }
    }
  }

  final List<Rect> merged = <Rect>[];
  for (final band in lineBands) {
    band.sort((a, b) => a.left.compareTo(b.left));
    Rect acc = band.first;
    for (int i = 1; i < band.length; i++) {
      final next = band[i];
      final maxGap = math.max(2.5, acc.height * 0.35);
      if (next.left <= acc.right + maxGap) {
        acc = Rect.fromLTRB(
          math.min(acc.left, next.left),
          math.min(acc.top, next.top),
          math.max(acc.right, next.right),
          math.max(acc.bottom, next.bottom),
        );
      } else {
        merged.add(roundPdfRect(acc));
        acc = next;
      }
    }
    merged.add(roundPdfRect(acc));
  }
  return merged;
}

/// Counts '%%EOF' markers in [bytes] to detect accumulated incremental PDF revisions.
int countPdfEofMarkers(Uint8List bytes) {
  int count = 0;
  final limit = bytes.length - 4;
  for (int i = 0; i < limit; i++) {
    if (bytes[i] == 37 &&
        bytes[i + 1] == 37 &&
        bytes[i + 2] == 69 &&
        bytes[i + 3] == 79 &&
        bytes[i + 4] == 70) {
      count++;
      i += 4;
    }
  }
  return count;
}

List<Rect> computeFallbackPageBounds(
  List<(double w, double h)> pdfSizes,
  double viewportWidth,
  double pageSpacing,
) {
  final effectiveViewportWidth = viewportWidth > 0 ? viewportWidth : 400.0;
  final bounds = <Rect>[];
  double currentY = 0.0;
  for (final (pw, ph) in pdfSizes) {
    final renderedH = effectiveViewportWidth * (ph / math.max(1.0, pw));
    bounds.add(Rect.fromLTWH(0, currentY, effectiveViewportWidth, renderedH));
    currentY += renderedH + pageSpacing;
  }
  return bounds;
}

int findOrigPageIndex(List<Rect> origPageBounds, double y) {
  if (origPageBounds.isEmpty) return -1;
  for (int i = 0; i < origPageBounds.length; i++) {
    final bounds = origPageBounds[i];
    final splitY = i < origPageBounds.length - 1
        ? (bounds.bottom + origPageBounds[i + 1].top) / 2.0
        : double.infinity;
    if (y <= splitY) {
      return i;
    }
  }
  return origPageBounds.length - 1;
}

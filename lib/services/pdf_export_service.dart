import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../controllers/drawing_controller.dart';
import '../models/editor_models.dart';
import 'editor_settings_service.dart';
import 'latex_rasterizer.dart';
import 'pdf_image_optimizer.dart';

class PdfExportService {
  PdfExportService._();

  static final RegExp _jpKanaRegex = RegExp(r'[\u3040-\u30ff]');
  static final RegExp _krHangulRegex = RegExp(r'[\uac00-\ud7af]');

  static sf.PdfColor _toPdfColor(Color c) {
    return sf.PdfColor(
      (c.r * 255.0).round().clamp(0, 255),
      (c.g * 255.0).round().clamp(0, 255),
      (c.b * 255.0).round().clamp(0, 255),
      (c.a * 255.0).round().clamp(0, 255),
    );
  }

  /// Quantizes a PDF point coordinate to 0.1 pt (1/720 inch) precision to reduce
  /// floating-point string bloat and improve Deflate compression of content streams.
  static double roundPdfCoord(double value) {
    return (value * 10.0).roundToDouble() / 10.0;
  }

  static Offset roundPdfOffset(Offset p) {
    return Offset(roundPdfCoord(p.dx), roundPdfCoord(p.dy));
  }

  static Rect roundPdfRect(Rect r) {
    final left = roundPdfCoord(r.left);
    final top = roundPdfCoord(r.top);
    final right = roundPdfCoord(r.right);
    final bottom = roundPdfCoord(r.bottom);
    return Rect.fromLTRB(left, top, math.max(left, right), math.max(top, bottom));
  }

  /// Simplifies a polyline in PDF point space using iterative Ramer-Douglas-Peucker (RDP)
  /// and quantizes surviving vertices to 0.1 pt precision.
  static List<Offset> simplifyStrokePoints(
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
  static List<Rect> mergeCollinearRects(List<Rect> rects) {
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
  static int _countPdfEofMarkers(Uint8List bytes) {
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

  /// Atomically writes [bytes] to [targetFile] via a flushed sibling temporary file
  /// so an interrupted write or power loss never corrupts the existing file.
  static Future<void> atomicWriteBytes(File targetFile, List<int> bytes) async {
    final parent = targetFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final tempPath = '${targetFile.path}.tmp.${DateTime.now().microsecondsSinceEpoch}';
    final tempFile = File(tempPath);
    try {
      await tempFile.writeAsBytes(bytes, flush: true);
      final writtenLen = await tempFile.length();
      if (writtenLen != bytes.length) {
        throw FileSystemException(
          'Incomplete temporary write ($writtenLen of ${bytes.length} bytes)',
          tempPath,
        );
      }
      try {
        await tempFile.rename(targetFile.path);
      } on FileSystemException {
        // Fallback for filesystems (e.g., certain Android SD card FUSE mounts)
        // that disallow rename over an existing file
        await tempFile.copy(targetFile.path);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } finally {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  /// Atomically writes UTF-8 [content] to [targetFile].
  static Future<void> atomicWriteString(File targetFile, String content) {
    return atomicWriteBytes(targetFile, utf8.encode(content));
  }

  /// Renders all annotations from [drawingController], applies staged page deletions
  /// and blank page additions, and returns the resulting PDF bytes.
  static Future<Uint8List> buildExportBytes({
    required Uint8List baseBytes,
    required DrawingController drawingController,
    required double viewportWidth,
    required AppFontFamily textBoxFont,
    List<int> deletedZeroIndexedPages = const [],
    int addedPagesCount = 0,
    double pageSpacing = 4.0,
    List<Rect>? pageDocBounds,
  }) async {
    final doc = sf.PdfDocument(inputBytes: baseBytes);
    try {
      doc.compressionLevel = sf.PdfCompressionLevel.best;
      doc.fileStructure.crossReferenceType = sf.PdfCrossReferenceType.crossReferenceStream;

      final origPageCount = doc.pages.count;
      final effectiveViewportWidth = viewportWidth > 0 ? viewportWidth : 400.0;

      // 1. Compute original page document-space bounds BEFORE mutating doc.pages,
      // because all annotations in drawingController were authored against original pages.
      final List<Rect> origPageBounds;
      if (pageDocBounds != null && pageDocBounds.length == origPageCount) {
        origPageBounds = List<Rect>.from(pageDocBounds);
      } else {
        origPageBounds = [];
        double currentY = 0.0;
        for (int i = 0; i < origPageCount; i++) {
          final pSize = doc.pages[i].size;
          final renderedH = effectiveViewportWidth * (pSize.height / pSize.width);
          origPageBounds.add(Rect.fromLTWH(0, currentY, effectiveViewportWidth, renderedH));
          currentY += renderedH + pageSpacing;
        }
      }

      // 2. Build mapping from original 0-based page index -> post-deletion 0-based page index (-1 if deleted)
      final deletedSet = deletedZeroIndexedPages
          .where((idx) => idx >= 0 && idx < origPageCount)
          .toSet();

      // Disable incremental append when pages are deleted (so removed page streams/images
      // are garbage-collected) or when multiple incremental trailers have accumulated.
      if (deletedSet.isNotEmpty ||
          (baseBytes.length <= 25 * 1024 * 1024 && _countPdfEofMarkers(baseBytes) >= 3)) {
        doc.fileStructure.incrementalUpdate = false;
      }

      final List<int> oldToNewPageIdx = List<int>.filled(origPageCount, -1);
      int nextNewIdx = 0;
      for (int i = 0; i < origPageCount; i++) {
        if (!deletedSet.contains(i)) {
          oldToNewPageIdx[i] = nextNewIdx++;
        }
      }

      // 3. Delete pages in reverse order so indices stay stable during removal
      final sortedDeletes = deletedSet.toList()..sort((a, b) => b.compareTo(a));
      for (final pIdx in sortedDeletes) {
        if (pIdx >= 0 && pIdx < doc.pages.count) {
          doc.pages.removeAt(pIdx);
        }
      }

      // 4. Append newly added blank pages at the end
      for (int i = 0; i < addedPagesCount; i++) {
        doc.pages.add();
      }

      int findOrigPageIndex(double y) {
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

      // 5. Render text annotations with collinear rect merging & shared highlight ExtGState
      int activeHighlightPageIdx = -1;
      int activeHighlightColorArgb = 0;
      sf.PdfPath? activeHighlightPath;

      void flushHighlightBatch({bool closePageTransparency = true}) {
        if (activeHighlightPageIdx >= 0 && activeHighlightPath != null) {
          final hPage = doc.pages[activeHighlightPageIdx];
          final brush = sf.PdfSolidBrush(_toPdfColor(Color(activeHighlightColorArgb)));
          hPage.graphics.drawPath(activeHighlightPath!, brush: brush);
          activeHighlightPath = null;
        }
        if (closePageTransparency && activeHighlightPageIdx >= 0) {
          doc.pages[activeHighlightPageIdx].graphics.restore();
          activeHighlightPageIdx = -1;
        }
      }

      for (final ta in drawingController.textAnnotations) {
        final origIdx = ta.pageNumber - 1;
        if (origIdx < 0 || origIdx >= origPageCount) continue;
        final newIdx = oldToNewPageIdx[origIdx];
        if (newIdx < 0 || newIdx >= doc.pages.count) continue;

        final page = doc.pages[newIdx];
        final bounds = origPageBounds[origIdx];
        final scaleX = page.size.width / bounds.width;
        final scaleY = page.size.height / bounds.height;

        final scaledRects = <Rect>[
          for (final r in ta.rects)
            Rect.fromLTWH(
              (r.left - bounds.left) * scaleX,
              (r.top - bounds.top) * scaleY,
              r.width * scaleX,
              r.height * scaleY,
            ),
        ];
        final mergedRects = mergeCollinearRects(scaledRects);
        if (mergedRects.isEmpty) continue;

        if (ta.type == TextAnnotationType.highlight) {
          final colorArgb = ta.color.toARGB32();
          if (activeHighlightPageIdx != newIdx) {
            flushHighlightBatch(closePageTransparency: true);
            page.graphics.save();
            page.graphics.setTransparency(0.35, mode: sf.PdfBlendMode.multiply);
            activeHighlightPageIdx = newIdx;
            activeHighlightColorArgb = colorArgb;
            activeHighlightPath = sf.PdfPath();
          } else if (activeHighlightColorArgb != colorArgb || activeHighlightPath == null) {
            flushHighlightBatch(closePageTransparency: false);
            activeHighlightColorArgb = colorArgb;
            activeHighlightPath = sf.PdfPath();
          }
          for (final pdfRect in mergedRects) {
            activeHighlightPath!.addRectangle(pdfRect);
          }
        } else {
          flushHighlightBatch(closePageTransparency: true);
          final pen = sf.PdfPen(
            _toPdfColor(ta.color),
            width: math.max(0.5, roundPdfCoord(1.5 * scaleX)),
          );
          final linePoints = <Offset>[];
          final lineTypes = <int>[];
          for (final pdfRect in mergedRects) {
            final y = roundPdfCoord(
              ta.type == TextAnnotationType.underline ? pdfRect.bottom : pdfRect.center.dy,
            );
            linePoints.add(Offset(pdfRect.left, y));
            linePoints.add(Offset(pdfRect.right, y));
            lineTypes.add(0);
            lineTypes.add(1);
          }
          if (linePoints.isNotEmpty) {
            page.graphics.drawPath(
              sf.PdfPath(points: linePoints, pathTypes: lineTypes),
              pen: pen,
            );
          }
        }
      }
      flushHighlightBatch(closePageTransparency: true);

      // 6. Draw strokes using RDP simplification and contiguous same-style PdfPath batching
      int strokeBatchPageIdx = -1;
      int strokeBatchColorArgb = 0;
      int strokeBatchWidthTenths = 0;
      List<Offset> strokeBatchPoints = <Offset>[];
      List<int> strokeBatchTypes = <int>[];

      void flushStrokeBatch() {
        if (strokeBatchPageIdx < 0 || strokeBatchPoints.isEmpty) return;
        final bPage = doc.pages[strokeBatchPageIdx];
        final pen = sf.PdfPen(
          _toPdfColor(Color(strokeBatchColorArgb)),
          width: strokeBatchWidthTenths / 10.0,
        )
          ..lineCap = sf.PdfLineCap.round
          ..lineJoin = sf.PdfLineJoin.round;
        final path = sf.PdfPath(points: strokeBatchPoints, pathTypes: strokeBatchTypes);
        bPage.graphics.drawPath(path, pen: pen);
        strokeBatchPoints = <Offset>[];
        strokeBatchTypes = <int>[];
        strokeBatchPageIdx = -1;
      }

      for (final stroke in drawingController.strokes) {
        if (stroke.points.isEmpty) continue;
        final origIdx = findOrigPageIndex(stroke.points.first.offset.dy);
        if (origIdx < 0 || origIdx >= origPageCount) continue;
        final newIdx = oldToNewPageIdx[origIdx];
        if (newIdx < 0 || newIdx >= doc.pages.count) continue;

        final page = doc.pages[newIdx];
        final bounds = origPageBounds[origIdx];
        final scaleX = page.size.width / bounds.width;
        final scaleY = page.size.height / bounds.height;

        if (stroke.points.length == 1) {
          flushStrokeBatch();
          final pt = roundPdfOffset(Offset(
            (stroke.points.first.offset.dx - bounds.left) * scaleX,
            (stroke.points.first.offset.dy - bounds.top) * scaleY,
          ));
          final r = math.max(
            0.5,
            roundPdfCoord((stroke.strokeWidth * stroke.points.first.pressure / 2.0) * scaleX),
          );
          final brush = sf.PdfSolidBrush(_toPdfColor(stroke.color));
          page.graphics.drawEllipse(Rect.fromCircle(center: pt, radius: r), brush: brush);
          continue;
        }

        final List<Offset> preFiltered = <Offset>[];
        Offset? lastPt;
        for (final p in stroke.points) {
          final pt = Offset(
            (p.offset.dx - bounds.left) * scaleX,
            (p.offset.dy - bounds.top) * scaleY,
          );
          if (lastPt == null || (pt - lastPt).distanceSquared > 0.09) {
            preFiltered.add(pt);
            lastPt = pt;
          }
        }
        // Always preserve exact stroke endpoint before RDP
        final rawLast = Offset(
          (stroke.points.last.offset.dx - bounds.left) * scaleX,
          (stroke.points.last.offset.dy - bounds.top) * scaleY,
        );
        if (preFiltered.isEmpty || (rawLast - preFiltered.last).distanceSquared > 1e-4) {
          preFiltered.add(rawLast);
        }

        final docPoints = simplifyStrokePoints(preFiltered, epsilon: 0.25);
        if (docPoints.length < 2) {
          if (docPoints.isNotEmpty) {
            flushStrokeBatch();
            final r = math.max(0.5, roundPdfCoord((stroke.strokeWidth / 2.0) * scaleX));
            final brush = sf.PdfSolidBrush(_toPdfColor(stroke.color));
            page.graphics.drawEllipse(
              Rect.fromCircle(center: docPoints.first, radius: r),
              brush: brush,
            );
          }
          continue;
        }

        final colorArgb = stroke.color.toARGB32();
        final widthTenths = math.max(5, (stroke.strokeWidth * scaleX * 10.0).round());

        if (strokeBatchPageIdx != newIdx ||
            strokeBatchColorArgb != colorArgb ||
            strokeBatchWidthTenths != widthTenths) {
          flushStrokeBatch();
          strokeBatchPageIdx = newIdx;
          strokeBatchColorArgb = colorArgb;
          strokeBatchWidthTenths = widthTenths;
        }

        strokeBatchPoints.addAll(docPoints);
        strokeBatchTypes.add(0);
        for (int i = 1; i < docPoints.length; i++) {
          strokeBatchTypes.add(1);
        }
      }
      flushStrokeBatch();

      // 7. Draw geometric shapes with quantized coordinates
      for (final shape in drawingController.shapes) {
        final origIdx = findOrigPageIndex(shape.start.dy);
        if (origIdx < 0 || origIdx >= origPageCount) continue;
        final newIdx = oldToNewPageIdx[origIdx];
        if (newIdx < 0 || newIdx >= doc.pages.count) continue;

        final page = doc.pages[newIdx];
        final bounds = origPageBounds[origIdx];
        final scaleX = page.size.width / bounds.width;
        final scaleY = page.size.height / bounds.height;

        final start = roundPdfOffset(Offset(
          (shape.start.dx - bounds.left) * scaleX,
          (shape.start.dy - bounds.top) * scaleY,
        ));
        final end = roundPdfOffset(Offset(
          (shape.end.dx - bounds.left) * scaleX,
          (shape.end.dy - bounds.top) * scaleY,
        ));
        final pen = sf.PdfPen(
          _toPdfColor(shape.color),
          width: math.max(0.5, roundPdfCoord(shape.strokeWidth * scaleX)),
        );

        switch (shape.type) {
          case ShapeType.rectangle:
            page.graphics.drawRectangle(bounds: Rect.fromPoints(start, end), pen: pen);
            break;
          case ShapeType.circle:
            page.graphics.drawEllipse(Rect.fromPoints(start, end), pen: pen);
            break;
          case ShapeType.line:
            page.graphics.drawLine(pen, start, end);
            break;
          case ShapeType.arrow:
            final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
            final arrowLength = math.max(shape.strokeWidth * 4.0 * scaleX, 12.0);
            const arrowAngle = math.pi / 6;

            final p1 = roundPdfOffset(Offset(
              end.dx - arrowLength * math.cos(angle - arrowAngle),
              end.dy - arrowLength * math.sin(angle - arrowAngle),
            ));
            final p2 = roundPdfOffset(Offset(
              end.dx - arrowLength * math.cos(angle + arrowAngle),
              end.dy - arrowLength * math.sin(angle + arrowAngle),
            ));

            final arrowPath = sf.PdfPath(
              points: <Offset>[start, end, p1, end, p2],
              pathTypes: const <int>[0, 1, 0, 1, 1],
            );
            page.graphics.drawPath(arrowPath, pen: pen);
            break;
        }
      }

      // 8. Draw text boxes (cached PdfFont dictionaries, deduplicated LaTeX & fallback bitmaps)
      final Map<String, sf.PdfFont> fontCache = {};
      final Map<String, ({sf.PdfBitmap? bitmap, Offset offset, Size size})> latexBitmapCache = {};
      final Map<String, ({sf.PdfBitmap? bitmap, Offset offset, Size size})> fallbackBitmapCache = {};
      final wordWrapFormat = sf.PdfStringFormat(wordWrap: sf.PdfWordWrapType.word);

      for (final tb in drawingController.textBoxes) {
        if (tb.text.trim().isEmpty) continue;
        final origIdx = findOrigPageIndex(tb.position.dy);
        if (origIdx < 0 || origIdx >= origPageCount) continue;
        final newIdx = oldToNewPageIdx[origIdx];
        if (newIdx < 0 || newIdx >= doc.pages.count) continue;

        final page = doc.pages[newIdx];
        final bounds = origPageBounds[origIdx];
        final scaleX = page.size.width / bounds.width;
        final scaleY = page.size.height / bounds.height;

        final pos = roundPdfOffset(Offset(
          ((tb.position.dx - bounds.left) + 4) * scaleX,
          (tb.position.dy + 2 - bounds.top) * scaleY,
        ));

        if (tb.isLatex) {
          final targetRatio = LatexRasterizer.computeTargetPixelRatio(scaleX);
          final cacheKey =
              '${tb.fontSize.toStringAsFixed(2)}|${tb.color.toARGB32()}|${targetRatio.toStringAsFixed(2)}|${tb.text}';
          var cached = latexBitmapCache[cacheKey];
          if (cached == null) {
            final res = await LatexRasterizer.rasterize(
              latex: tb.text,
              fontSize: tb.fontSize,
              color: tb.color,
              pixelRatio: targetRatio,
            );
            if (res != null && res.bytes.isNotEmpty) {
              cached = (
                bitmap: sf.PdfBitmap(res.bytes),
                offset: res.offset,
                size: res.size,
              );
            } else {
              cached = (bitmap: null, offset: Offset.zero, size: Size.zero);
            }
            latexBitmapCache[cacheKey] = cached;
          }

          final pdfImage = cached.bitmap;
          if (pdfImage != null) {
            page.graphics.drawImage(
              pdfImage,
              Rect.fromLTWH(
                roundPdfCoord(pos.dx + cached.offset.dx * scaleX),
                roundPdfCoord(pos.dy + cached.offset.dy * scaleY),
                roundPdfCoord(cached.size.width * scaleX),
                roundPdfCoord(cached.size.height * scaleY),
              ),
            );
          }
          continue;
        }

        final tbWidth = roundPdfCoord((tb.width ?? 220.0) * scaleX);
        final pdfFontSize = (tb.fontSize * scaleX * 20.0).round() / 20.0;

        final isPureAscii = tb.text.codeUnits.every(
          (c) => (c >= 32 && c < 127) || c == 10 || c == 13 || c == 9,
        );

        String fontCategory;
        if (isPureAscii) {
          fontCategory = 'ascii_${textBoxFont.name}';
        } else if (_jpKanaRegex.hasMatch(tb.text)) {
          fontCategory = textBoxFont == AppFontFamily.serif ? 'jp_serif' : 'jp_sans';
        } else if (_krHangulRegex.hasMatch(tb.text)) {
          fontCategory = textBoxFont == AppFontFamily.serif ? 'kr_serif' : 'kr_sans';
        } else {
          fontCategory = 'cjk_song';
        }

        final fontKey = '$fontCategory|${pdfFontSize.toStringAsFixed(2)}';
        final font = fontCache.putIfAbsent(fontKey, () {
          switch (fontCategory) {
            case 'ascii_sansSerif':
              return sf.PdfStandardFont(sf.PdfFontFamily.helvetica, pdfFontSize);
            case 'ascii_serif':
              return sf.PdfStandardFont(sf.PdfFontFamily.timesRoman, pdfFontSize);
            case 'ascii_monospace':
              return sf.PdfStandardFont(sf.PdfFontFamily.courier, pdfFontSize);
            case 'jp_serif':
              return sf.PdfCjkStandardFont(sf.PdfCjkFontFamily.heiseiMinchoW3, pdfFontSize);
            case 'jp_sans':
              return sf.PdfCjkStandardFont(sf.PdfCjkFontFamily.heiseiKakuGothicW5, pdfFontSize);
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
              return sf.PdfCjkStandardFont(sf.PdfCjkFontFamily.sinoTypeSongLight, pdfFontSize);
          }
        });

        final brush = sf.PdfSolidBrush(_toPdfColor(tb.color));

        try {
          page.graphics.drawString(
            tb.text,
            font,
            bounds: Rect.fromLTWH(
              pos.dx,
              pos.dy,
              tbWidth,
              roundPdfCoord(1000 * scaleY),
            ),
            brush: brush,
            format: wordWrapFormat,
          );
        } catch (_) {
          final fallbackKey =
              '${pdfFontSize.toStringAsFixed(2)}|${tb.color.toARGB32()}|${tbWidth.toStringAsFixed(1)}|${tb.text}';
          var cachedFallback = fallbackBitmapCache[fallbackKey];
          if (cachedFallback == null) {
            const renderScale = 2.0;
            final textPainter = TextPainter(
              text: TextSpan(
                text: tb.text,
                style: TextStyle(
                  color: tb.color,
                  fontSize: pdfFontSize * renderScale,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
              textDirection: TextDirection.ltr,
            );
            OptimizedPngResult? optPng;
            try {
              textPainter.layout(maxWidth: tbWidth * renderScale);
              final pWidth = math.max(1, textPainter.width.ceil());
              final pHeight = math.max(1, textPainter.height.ceil());

              final recorder = ui.PictureRecorder();
              final canvas = Canvas(recorder);
              textPainter.paint(canvas, Offset.zero);

              final picture = recorder.endRecording();
              ui.Image? img;
              try {
                img = await picture.toImage(pWidth, pHeight);
                final rawData = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
                if (rawData != null) {
                  optPng = PdfImageOptimizer.encodeOptimizedPngFromRgba(
                    rawStraightRgba: rawData.buffer.asUint8List(
                      rawData.offsetInBytes,
                      rawData.lengthInBytes,
                    ),
                    width: pWidth,
                    height: pHeight,
                    logicalSize: Size(pWidth / renderScale, pHeight / renderScale),
                    cropTransparentMargins: true,
                  );
                }
              } finally {
                img?.dispose();
                picture.dispose();
              }
            } finally {
              textPainter.dispose();
            }

            if (optPng != null && optPng.bytes.isNotEmpty) {
              cachedFallback = (
                bitmap: sf.PdfBitmap(optPng.bytes),
                offset: optPng.offset,
                size: optPng.size,
              );
            } else {
              cachedFallback = (bitmap: null, offset: Offset.zero, size: Size.zero);
            }
            fallbackBitmapCache[fallbackKey] = cachedFallback;
          }

          if (cachedFallback.bitmap != null) {
            page.graphics.drawImage(
              cachedFallback.bitmap!,
              Rect.fromLTWH(
                roundPdfCoord(pos.dx + cachedFallback.offset.dx),
                roundPdfCoord(pos.dy + cachedFallback.offset.dy),
                roundPdfCoord(cachedFallback.size.width),
                roundPdfCoord(cachedFallback.size.height),
              ),
            );
          }
        }
      }

      // 9. Draw pasted images (DPI-downsampled, opaque-alpha-stripped, and content-deduplicated)
      final Map<String, sf.PdfBitmap> pastedImageCache = {};
      for (final img in drawingController.images) {
        final origIdx = findOrigPageIndex(img.position.dy);
        if (origIdx < 0 || origIdx >= origPageCount) continue;
        final newIdx = oldToNewPageIdx[origIdx];
        if (newIdx < 0 || newIdx >= doc.pages.count) continue;

        final page = doc.pages[newIdx];
        final bounds = origPageBounds[origIdx];
        final scaleX = page.size.width / bounds.width;
        final scaleY = page.size.height / bounds.height;

        final pos = roundPdfOffset(Offset(
          (img.position.dx - bounds.left) * scaleX,
          (img.position.dy - bounds.top) * scaleY,
        ));
        final pdfW = roundPdfCoord(img.width * scaleX);
        final pdfH = roundPdfCoord(img.height * scaleY);
        final bucketW = (pdfW / 16.0).ceil() * 16;
        final bucketH = (pdfH / 16.0).ceil() * 16;
        final imgCacheKey =
            '${PdfImageOptimizer.computeContentKey(img.imageBytes)}|${bucketW}x$bucketH';

        var bmp = pastedImageCache[imgCacheKey];
        if (bmp == null) {
          final optimizedBytes = await PdfImageOptimizer.optimizeForPdf(
            img.imageBytes,
            targetPdfWidthPt: pdfW,
            targetPdfHeightPt: pdfH,
          );
          bmp = sf.PdfBitmap(optimizedBytes);
          pastedImageCache[imgCacheKey] = bmp;
        }

        page.graphics.drawImage(
          bmp,
          Rect.fromLTWH(pos.dx, pos.dy, pdfW, pdfH),
        );
      }

      return doc.saveAsBytesSync();
    } finally {
      doc.dispose();
    }
  }

  /// Builds exported PDF bytes and atomically writes them to [file].
  static Future<Uint8List> exportToFile({
    required File file,
    required Uint8List baseBytes,
    required DrawingController drawingController,
    required double viewportWidth,
    required AppFontFamily textBoxFont,
    List<int> deletedZeroIndexedPages = const [],
    int addedPagesCount = 0,
    List<Rect>? pageDocBounds,
  }) async {
    final finalBytes = await buildExportBytes(
      baseBytes: baseBytes,
      drawingController: drawingController,
      viewportWidth: viewportWidth,
      textBoxFont: textBoxFont,
      deletedZeroIndexedPages: deletedZeroIndexedPages,
      addedPagesCount: addedPagesCount,
      pageDocBounds: pageDocBounds,
    );
    await atomicWriteBytes(file, finalBytes);
    return finalBytes;
  }
}

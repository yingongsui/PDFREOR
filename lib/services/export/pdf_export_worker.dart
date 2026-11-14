import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../models/editor_models.dart';
import '../annotation_persistence_codec.dart';
import 'pdf_editable_layer_helper.dart';
import 'pdf_export_geometry.dart';
import 'pdf_export_models.dart';

ExportWorkerResult runPdfExportWorker(ExportJobPayload payload) {
  final doc = sf.PdfDocument(inputBytes: payload.baseBytes);
  try {
    doc.compressionLevel = sf.PdfCompressionLevel.best;
    doc.fileStructure.crossReferenceType = sf.PdfCrossReferenceType.crossReferenceStream;

    final origPageCount = doc.pages.count;

    // 1. Compute original page document-space bounds BEFORE mutating doc.pages.
    final List<Rect> origPageBounds;
    if (payload.pageDocBounds != null && payload.pageDocBounds!.length == origPageCount) {
      origPageBounds = [
        for (final (l, t, w, h) in payload.pageDocBounds!) Rect.fromLTWH(l, t, w, h),
      ];
    } else {
      final pdfSizes = [
        for (int i = 0; i < origPageCount; i++)
          (doc.pages[i].size.width, doc.pages[i].size.height),
      ];
      origPageBounds = computeFallbackPageBounds(
        pdfSizes,
        payload.viewportWidth,
        payload.pageSpacing,
      );
    }

    // 2. Build mapping from original 0-based page index -> post-deletion 0-based page index
    final deletedSet = payload.deletedZeroIndexedPages
        .where((idx) => idx >= 0 && idx < origPageCount)
        .toSet();

    // Always remove stale JSON attachment; only strip tagged annotation streams when
    // re-emitting Advanced editable streams (so saving a formerly-Advanced file in Standard
    // mode never drops previously baked visual annotations not in DrawingController).
    final strippedStreams = payload.embedEditableData
        ? PdfEditableLayerHelper.stripAnnotationStreams(doc)
        : false;
    final removedAttachment = PdfEditableLayerHelper.removeAnnotationAttachments(doc);

    if (deletedSet.isNotEmpty ||
        ((strippedStreams || removedAttachment || payload.embedEditableData) &&
            payload.baseBytes.length <= 25 * 1024 * 1024) ||
        (payload.baseBytes.length <= 25 * 1024 * 1024 &&
            countPdfEofMarkers(payload.baseBytes) >= 3)) {
      doc.fileStructure.incrementalUpdate = false;
    }

    final List<int> oldToNewPageIdx = List<int>.filled(origPageCount, -1);
    int nextNewIdx = 0;
    for (int i = 0; i < origPageCount; i++) {
      if (!deletedSet.contains(i)) {
        oldToNewPageIdx[i] = nextNewIdx++;
      }
    }

    // 3. Delete pages in reverse order
    final sortedDeletes = deletedSet.toList()..sort((a, b) => b.compareTo(a));
    for (final pIdx in sortedDeletes) {
      if (pIdx >= 0 && pIdx < doc.pages.count) {
        doc.pages.removeAt(pIdx);
      }
    }

    // 4. Append newly added blank pages
    for (int i = 0; i < payload.addedPagesCount; i++) {
      doc.pages.add();
    }

    final preDrawSnapshots = payload.embedEditableData
        ? PdfEditableLayerHelper.capturePreDrawSnapshots(doc)
        : const <int, PagePreDrawSnapshot>{};

    // 5. Render text annotations with collinear rect merging & shared highlight ExtGState
    _drawExportTextAnnotations(
      doc: doc,
      annotations: payload.textAnnotations,
      origPageBounds: origPageBounds,
      oldToNewPageIdx: oldToNewPageIdx,
    );

    // 6. Draw strokes using RDP simplification and contiguous same-style PdfPath batching
    _drawExportStrokes(
      doc: doc,
      strokes: payload.strokes,
      origPageBounds: origPageBounds,
      oldToNewPageIdx: oldToNewPageIdx,
    );

    // 7. Draw geometric shapes
    _drawExportShapes(
      doc: doc,
      shapes: payload.shapes,
      origPageBounds: origPageBounds,
      oldToNewPageIdx: oldToNewPageIdx,
    );

    // 8. Draw text boxes & pre-rasterized LaTeX formulas
    final Map<String, sf.PdfBitmap> bitmapCache = {};
    final missingFallbacks = _drawExportTextBoxes(
      doc: doc,
      payload: payload,
      origPageBounds: origPageBounds,
      oldToNewPageIdx: oldToNewPageIdx,
      bitmapCache: bitmapCache,
    );

    if (missingFallbacks.isNotEmpty) {
      return ExportWorkerResult(missingFallbacks: missingFallbacks);
    }

    // 9. Draw pasted images
    _drawExportImages(
      doc: doc,
      payload: payload,
      origPageBounds: origPageBounds,
      oldToNewPageIdx: oldToNewPageIdx,
      bitmapCache: bitmapCache,
    );

    if (payload.embedEditableData) {
      final postEditPageSizes = <(double w, double h)>[
        for (int i = 0; i < doc.pages.count; i++)
          (doc.pages[i].size.width, doc.pages[i].size.height),
      ];
      final bundle = AnnotationPersistenceCodec.buildBundleFromExportPayload(
        payload: payload,
        origPageBounds: origPageBounds,
        oldToNewPageIdx: oldToNewPageIdx,
        postEditPageSizes: postEditPageSizes,
      );
      if (!bundle.isEmpty) {
        final taggedPages = <int>{
          for (final s in bundle.strokes) s.pageIndex,
          for (final sh in bundle.shapes) sh.pageIndex,
          for (final tb in bundle.textBoxes) tb.pageIndex,
          for (final im in bundle.images) im.pageIndex,
          for (final ta in bundle.textAnnotations) ta.pageIndex,
        };
        for (final pIdx in taggedPages) {
          if (pIdx >= 0 && pIdx < doc.pages.count) {
            PdfEditableLayerHelper.tagAddedPageArtifacts(
              doc.pages[pIdx],
              preDrawSnapshots[pIdx],
            );
          }
        }
        final gzBytes = AnnotationPersistenceCodec.encodeGzip(bundle);
        PdfEditableLayerHelper.writeAnnotationAttachment(doc, gzBytes);
      }
    }

    return ExportWorkerResult(pdfBytes: doc.saveAsBytesSync());
  } finally {
    doc.dispose();
  }
}

void _drawExportTextAnnotations({
  required sf.PdfDocument doc,
  required List<ExportTextAnnotationDto> annotations,
  required List<Rect> origPageBounds,
  required List<int> oldToNewPageIdx,
}) {
  final origPageCount = origPageBounds.length;
  int activeHighlightPageIdx = -1;
  int activeHighlightColorArgb = 0;
  sf.PdfPath? activeHighlightPath;

  void flushHighlightBatch({bool closePageTransparency = true}) {
    if (activeHighlightPageIdx >= 0 && activeHighlightPath != null) {
      final hPage = doc.pages[activeHighlightPageIdx];
      final brush = sf.PdfSolidBrush(toPdfColor(activeHighlightColorArgb));
      hPage.graphics.drawPath(activeHighlightPath!, brush: brush);
      activeHighlightPath = null;
    }
    if (closePageTransparency && activeHighlightPageIdx >= 0) {
      doc.pages[activeHighlightPageIdx].graphics.restore();
      activeHighlightPageIdx = -1;
    }
  }

  for (final ta in annotations) {
    final origIdx = ta.pageNumber - 1;
    if (origIdx < 0 || origIdx >= origPageCount) continue;
    final newIdx = oldToNewPageIdx[origIdx];
    if (newIdx < 0 || newIdx >= doc.pages.count) continue;

    final page = doc.pages[newIdx];
    final bounds = origPageBounds[origIdx];
    final scaleX = page.size.width / bounds.width;
    final scaleY = page.size.height / bounds.height;

    final scaledRects = <Rect>[
      for (final (rl, rt, rw, rh) in ta.rects)
        Rect.fromLTWH(
          (rl - bounds.left) * scaleX,
          (rt - bounds.top) * scaleY,
          rw * scaleX,
          rh * scaleY,
        ),
    ];
    final mergedRects = mergeCollinearRects(scaledRects);
    if (mergedRects.isEmpty) continue;

    if (ta.type == TextAnnotationType.highlight) {
      if (activeHighlightPageIdx != newIdx) {
        flushHighlightBatch(closePageTransparency: true);
        page.graphics.save();
        page.graphics.setTransparency(0.35, mode: sf.PdfBlendMode.multiply);
        activeHighlightPageIdx = newIdx;
        activeHighlightColorArgb = ta.colorArgb;
        activeHighlightPath = sf.PdfPath();
      } else if (activeHighlightColorArgb != ta.colorArgb || activeHighlightPath == null) {
        flushHighlightBatch(closePageTransparency: false);
        activeHighlightColorArgb = ta.colorArgb;
        activeHighlightPath = sf.PdfPath();
      }
      for (final pdfRect in mergedRects) {
        activeHighlightPath!.addRectangle(pdfRect);
      }
    } else {
      flushHighlightBatch(closePageTransparency: true);
      final pen = sf.PdfPen(
        toPdfColor(ta.colorArgb),
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
}

void _drawExportStrokes({
  required sf.PdfDocument doc,
  required List<ExportStrokeDto> strokes,
  required List<Rect> origPageBounds,
  required List<int> oldToNewPageIdx,
}) {
  final origPageCount = origPageBounds.length;
  int strokeBatchPageIdx = -1;
  int strokeBatchColorArgb = 0;
  int strokeBatchWidthTenths = 0;
  List<Offset> strokeBatchPoints = <Offset>[];
  List<int> strokeBatchTypes = <int>[];

  void flushStrokeBatch() {
    if (strokeBatchPageIdx < 0 || strokeBatchPoints.isEmpty) return;
    final bPage = doc.pages[strokeBatchPageIdx];
    final pen = sf.PdfPen(
      toPdfColor(strokeBatchColorArgb),
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

  for (final stroke in strokes) {
    if (stroke.points.isEmpty) continue;
    final origIdx = findOrigPageIndex(origPageBounds, stroke.points.first.$2);
    if (origIdx < 0 || origIdx >= origPageCount) continue;
    final newIdx = oldToNewPageIdx[origIdx];
    if (newIdx < 0 || newIdx >= doc.pages.count) continue;

    final page = doc.pages[newIdx];
    final bounds = origPageBounds[origIdx];
    final scaleX = page.size.width / bounds.width;
    final scaleY = page.size.height / bounds.height;

    if (stroke.points.length == 1) {
      flushStrokeBatch();
      final (px, py, pressure) = stroke.points.first;
      final pt = roundPdfOffset(Offset(
        (px - bounds.left) * scaleX,
        (py - bounds.top) * scaleY,
      ));
      final r = math.max(
        0.5,
        roundPdfCoord((stroke.strokeWidth * pressure / 2.0) * scaleX),
      );
      final brush = sf.PdfSolidBrush(toPdfColor(stroke.colorArgb));
      page.graphics.drawEllipse(Rect.fromCircle(center: pt, radius: r), brush: brush);
      continue;
    }

    final List<Offset> preFiltered = <Offset>[];
    Offset? lastPt;
    for (final (px, py, _) in stroke.points) {
      final pt = Offset(
        (px - bounds.left) * scaleX,
        (py - bounds.top) * scaleY,
      );
      if (lastPt == null || (pt - lastPt).distanceSquared > 0.09) {
        preFiltered.add(pt);
        lastPt = pt;
      }
    }
    final (lx, ly, _) = stroke.points.last;
    final rawLast = Offset(
      (lx - bounds.left) * scaleX,
      (ly - bounds.top) * scaleY,
    );
    if (preFiltered.isEmpty || (rawLast - preFiltered.last).distanceSquared > 1e-4) {
      preFiltered.add(rawLast);
    }

    final docPoints = simplifyStrokePoints(preFiltered, epsilon: 0.25);
    if (docPoints.length < 2) {
      if (docPoints.isNotEmpty) {
        flushStrokeBatch();
        final r = math.max(0.5, roundPdfCoord((stroke.strokeWidth / 2.0) * scaleX));
        final brush = sf.PdfSolidBrush(toPdfColor(stroke.colorArgb));
        page.graphics.drawEllipse(
          Rect.fromCircle(center: docPoints.first, radius: r),
          brush: brush,
        );
      }
      continue;
    }

    final widthTenths = math.max(5, (stroke.strokeWidth * scaleX * 10.0).round());

    if (strokeBatchPageIdx != newIdx ||
        strokeBatchColorArgb != stroke.colorArgb ||
        strokeBatchWidthTenths != widthTenths) {
      flushStrokeBatch();
      strokeBatchPageIdx = newIdx;
      strokeBatchColorArgb = stroke.colorArgb;
      strokeBatchWidthTenths = widthTenths;
    }

    strokeBatchPoints.addAll(docPoints);
    strokeBatchTypes.add(0);
    for (int i = 1; i < docPoints.length; i++) {
      strokeBatchTypes.add(1);
    }
  }
  flushStrokeBatch();
}

void _drawExportShapes({
  required sf.PdfDocument doc,
  required List<ExportShapeDto> shapes,
  required List<Rect> origPageBounds,
  required List<int> oldToNewPageIdx,
}) {
  final origPageCount = origPageBounds.length;
  for (final shape in shapes) {
    final origIdx = findOrigPageIndex(origPageBounds, shape.startY);
    if (origIdx < 0 || origIdx >= origPageCount) continue;
    final newIdx = oldToNewPageIdx[origIdx];
    if (newIdx < 0 || newIdx >= doc.pages.count) continue;

    final page = doc.pages[newIdx];
    final bounds = origPageBounds[origIdx];
    final scaleX = page.size.width / bounds.width;
    final scaleY = page.size.height / bounds.height;

    final start = roundPdfOffset(Offset(
      (shape.startX - bounds.left) * scaleX,
      (shape.startY - bounds.top) * scaleY,
    ));
    final end = roundPdfOffset(Offset(
      (shape.endX - bounds.left) * scaleX,
      (shape.endY - bounds.top) * scaleY,
    ));
    final pen = sf.PdfPen(
      toPdfColor(shape.colorArgb),
      width: math.max(0.5, roundPdfCoord(shape.strokeWidth * scaleX)),
    );

    switch (shape.type) {
      case ShapeType.rectangle:
        page.graphics.drawRectangle(bounds: Rect.fromPoints(start, end), pen: pen);
        break;
      case ShapeType.roundedRectangle:
        final pdfRect = Rect.fromPoints(start, end);
        final docRect = Rect.fromPoints(
          Offset(shape.startX, shape.startY),
          Offset(shape.endX, shape.endY),
        );
        final maxRadius = math.min(pdfRect.width, pdfRect.height) * 0.5;
        final radius = math.min(
          maxRadius,
          roundPdfCoord(roundedRectCornerRadius(docRect) * scaleX),
        );
        if (radius <= 0.1) {
          page.graphics.drawRectangle(bounds: pdfRect, pen: pen);
        } else {
          final d = radius * 2.0;
          final rRectPath = sf.PdfPath()
            ..addArc(Rect.fromLTWH(pdfRect.left, pdfRect.top, d, d), 180, 90)
            ..addArc(Rect.fromLTWH(pdfRect.right - d, pdfRect.top, d, d), 270, 90)
            ..addArc(Rect.fromLTWH(pdfRect.right - d, pdfRect.bottom - d, d, d), 0, 90)
            ..addArc(Rect.fromLTWH(pdfRect.left, pdfRect.bottom - d, d, d), 90, 90)
            ..closeFigure();
          page.graphics.drawPath(rRectPath, pen: pen);
        }
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
}

List<FallbackRequest> _drawExportTextBoxes({
  required sf.PdfDocument doc,
  required ExportJobPayload payload,
  required List<Rect> origPageBounds,
  required List<int> oldToNewPageIdx,
  required Map<String, sf.PdfBitmap> bitmapCache,
}) {
  final origPageCount = origPageBounds.length;
  final Map<String, sf.PdfFont> fontCache = {};
  final wordWrapFormat = sf.PdfStringFormat(wordWrap: sf.PdfWordWrapType.word);
  final List<FallbackRequest> missingFallbacks = [];

  for (final tb in payload.textBoxes) {
    final origIdx = findOrigPageIndex(origPageBounds, tb.posY);
    if (origIdx < 0 || origIdx >= origPageCount) continue;
    final newIdx = oldToNewPageIdx[origIdx];
    if (newIdx < 0 || newIdx >= doc.pages.count) continue;

    final page = doc.pages[newIdx];
    final bounds = origPageBounds[origIdx];
    final scaleX = page.size.width / bounds.width;
    final scaleY = page.size.height / bounds.height;

    final pos = roundPdfOffset(Offset(
      ((tb.posX - bounds.left) + 4) * scaleX,
      (tb.posY + 2 - bounds.top) * scaleY,
    ));

    if (tb.isLatex) {
      final key = tb.preRasterKey;
      final raster = key != null ? payload.preRasterizedLatex[key] : null;
      if (key != null && raster != null) {
        final bmp = bitmapCache.putIfAbsent(
          'latex:$key',
          () => sf.PdfBitmap(raster.bytes),
        );
        page.graphics.drawImage(
          bmp,
          Rect.fromLTWH(
            roundPdfCoord(pos.dx + raster.offsetX * scaleX),
            roundPdfCoord(pos.dy + raster.offsetY * scaleY),
            roundPdfCoord(raster.width * scaleX),
            roundPdfCoord(raster.height * scaleY),
          ),
        );
      }
      continue;
    }

    final tbWidth = roundPdfCoord((tb.width ?? 220.0) * scaleX);
    final pdfFontSize = (tb.fontSize * scaleX * 20.0).round() / 20.0;
    final fontCategory = resolveExportFontCategory(tb.text, payload.textBoxFont);
    final fontKey = '$fontCategory|${pdfFontSize.toStringAsFixed(2)}';
    final font = fontCache.putIfAbsent(
      fontKey,
      () => createPdfFontForCategory(fontCategory, pdfFontSize),
    );
    final brush = sf.PdfSolidBrush(toPdfColor(tb.colorArgb));

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
          '${pdfFontSize.toStringAsFixed(2)}|${tb.colorArgb}|${tbWidth.toStringAsFixed(1)}|${tb.text}';
      if (payload.preRasterizedFallbacks.containsKey(fallbackKey)) {
        final raster = payload.preRasterizedFallbacks[fallbackKey];
        if (raster != null) {
          final bmp = bitmapCache.putIfAbsent(
            'fb:$fallbackKey',
            () => sf.PdfBitmap(raster.bytes),
          );
          page.graphics.drawImage(
            bmp,
            Rect.fromLTWH(
              roundPdfCoord(pos.dx + raster.offsetX),
              roundPdfCoord(pos.dy + raster.offsetY),
              roundPdfCoord(raster.width),
              roundPdfCoord(raster.height),
            ),
          );
        }
      } else {
        missingFallbacks.add(FallbackRequest(
          key: fallbackKey,
          text: tb.text,
          colorArgb: tb.colorArgb,
          fontSize: pdfFontSize,
          maxWidth: tbWidth,
        ));
      }
    }
  }

  return missingFallbacks;
}

void _drawExportImages({
  required sf.PdfDocument doc,
  required ExportJobPayload payload,
  required List<Rect> origPageBounds,
  required List<int> oldToNewPageIdx,
  required Map<String, sf.PdfBitmap> bitmapCache,
}) {
  final origPageCount = origPageBounds.length;
  for (final img in payload.images) {
    final origIdx = findOrigPageIndex(origPageBounds, img.posY);
    if (origIdx < 0 || origIdx >= origPageCount) continue;
    final newIdx = oldToNewPageIdx[origIdx];
    if (newIdx < 0 || newIdx >= doc.pages.count) continue;

    final page = doc.pages[newIdx];
    final bounds = origPageBounds[origIdx];
    final scaleX = page.size.width / bounds.width;
    final scaleY = page.size.height / bounds.height;

    final pos = roundPdfOffset(Offset(
      (img.posX - bounds.left) * scaleX,
      (img.posY - bounds.top) * scaleY,
    ));
    final pdfW = roundPdfCoord(img.width * scaleX);
    final pdfH = roundPdfCoord(img.height * scaleY);

    final optBytes = payload.optimizedImages[img.cacheKey];
    if (optBytes == null) continue;
    final bmp = bitmapCache.putIfAbsent(
      'img:${img.cacheKey}',
      () => sf.PdfBitmap(optBytes),
    );

    page.graphics.drawImage(
      bmp,
      Rect.fromLTWH(pos.dx, pos.dy, pdfW, pdfH),
    );
  }
}

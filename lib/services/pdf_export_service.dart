import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../controllers/drawing_controller.dart';
import 'annotation_persistence_codec.dart';
import 'atomic_file_store.dart';
import 'editor_settings_service.dart';
import 'export/pdf_editable_layer_helper.dart';
import 'export/pdf_export_geometry.dart' as geom;
import 'export/pdf_export_models.dart';
import 'export/pdf_export_worker.dart';
import 'latex_rasterizer.dart';
import 'pdf_image_optimizer.dart';

class PdfInspectResult {
  final bool hasEditablePayload;
  final PersistedAnnotationsBundle? bundle;
  final Uint8List? cleanBaseBytes;

  const PdfInspectResult({
    required this.hasEditablePayload,
    this.bundle,
    this.cleanBaseBytes,
  });
}

class PdfExportService {
  PdfExportService._();

  /// Quantizes a PDF point coordinate to 0.1 pt (1/720 inch) precision to reduce
  /// floating-point string bloat and improve Deflate compression of content streams.
  static double roundPdfCoord(double value) => geom.roundPdfCoord(value);

  /// Simplifies a polyline in PDF point space using iterative Ramer-Douglas-Peucker (RDP)
  /// and quantizes surviving vertices to 0.1 pt precision.
  static List<Offset> simplifyStrokePoints(
    List<Offset> points, {
    double epsilon = 0.25,
  }) =>
      geom.simplifyStrokePoints(points, epsilon: epsilon);

  /// Merges collinear horizontally adjacent or overlapping selection rectangles
  /// on the same text line into single span rectangles, reducing draw ops and avoiding
  /// dark multiply-blend seams between adjacent highlight boxes.
  static List<Rect> mergeCollinearRects(List<Rect> rects) =>
      geom.mergeCollinearRects(rects);

  /// Atomically writes [bytes] to [targetFile] via [AtomicFileStore].
  static Future<void> atomicWriteBytes(File targetFile, List<int> bytes) {
    return AtomicFileStore.writeBytes(targetFile, bytes);
  }

  /// Renders all annotations from [drawingController], applies staged page deletions
  /// and blank page additions, and returns the resulting PDF bytes.
  /// Heavy PDF parsing, path building, and compression run off the main UI isolate.
  static Future<Uint8List> buildExportBytes({
    required Uint8List baseBytes,
    required DrawingController drawingController,
    required double viewportWidth,
    required AppFontFamily textBoxFont,
    List<int> deletedZeroIndexedPages = const [],
    int addedPagesCount = 0,
    double pageSpacing = 4.0,
    List<Rect>? pageDocBounds,
    List<Size>? pdfPageSizes,
    bool embedEditableData = false,
  }) async {
    final hasLatex = drawingController.textBoxes.any(
      (tb) => tb.isLatex && tb.text.trim().isNotEmpty,
    );
    final hasImages = drawingController.images.isNotEmpty;

    List<(double w, double h)>? resolvedPdfSizes = pdfPageSizes
        ?.map((s) => (s.width, s.height))
        .toList(growable: false);
    if ((hasLatex || hasImages) && resolvedPdfSizes == null) {
      resolvedPdfSizes = await Isolate.run(() {
        final d = sf.PdfDocument(inputBytes: baseBytes);
        try {
          return [
            for (int i = 0; i < d.pages.count; i++)
              (d.pages[i].size.width, d.pages[i].size.height),
          ];
        } finally {
          d.dispose();
        }
      });
    }

    // Compute origPageBounds for pre-rasterizing LaTeX & pasted images when needed
    final List<Rect>? knownOrigPageBounds;
    if (resolvedPdfSizes != null) {
      if (pageDocBounds != null && pageDocBounds.length == resolvedPdfSizes.length) {
        knownOrigPageBounds = pageDocBounds;
      } else {
        knownOrigPageBounds = geom.computeFallbackPageBounds(
          resolvedPdfSizes,
          viewportWidth,
          pageSpacing,
        );
      }
    } else {
      knownOrigPageBounds = pageDocBounds;
    }

    // Pre-rasterize LaTeX formulas on the main isolate (requires Flutter BuildOwner/Math.tex)
    final Map<String, RasterizedBitmapDto?> preRasterizedLatex = {};
    final List<ExportTextBoxDto> textBoxDtos = [];
    for (int i = 0; i < drawingController.textBoxes.length; i++) {
      final tb = drawingController.textBoxes[i];
      if (tb.text.trim().isEmpty) continue;
      String? preRasterKey;
      if (tb.isLatex && knownOrigPageBounds != null && resolvedPdfSizes != null) {
        final origIdx = geom.findOrigPageIndex(knownOrigPageBounds, tb.position.dy);
        if (origIdx >= 0 && origIdx < resolvedPdfSizes.length) {
          final scaleX = resolvedPdfSizes[origIdx].$1 / knownOrigPageBounds[origIdx].width;
          final targetRatio = LatexRasterizer.computeTargetPixelRatio(scaleX);
          preRasterKey =
              '${tb.fontSize.toStringAsFixed(2)}|${tb.color.toARGB32()}|${targetRatio.toStringAsFixed(2)}|${tb.text}';
          if (!preRasterizedLatex.containsKey(preRasterKey)) {
            final res = await LatexRasterizer.rasterize(
              latex: tb.text,
              fontSize: tb.fontSize,
              color: tb.color,
              pixelRatio: targetRatio,
            );
            if (res != null && res.bytes.isNotEmpty) {
              preRasterizedLatex[preRasterKey] = RasterizedBitmapDto(
                bytes: res.bytes,
                offsetX: res.offset.dx,
                offsetY: res.offset.dy,
                width: res.size.width,
                height: res.size.height,
              );
            } else {
              preRasterizedLatex[preRasterKey] = null;
            }
          }
        }
      }
      textBoxDtos.add(ExportTextBoxDto(
        id: tb.id,
        index: i,
        text: tb.text,
        posX: tb.position.dx,
        posY: tb.position.dy,
        fontSize: tb.fontSize,
        colorArgb: tb.color.toARGB32(),
        width: tb.width,
        isLatex: tb.isLatex,
        preRasterKey: preRasterKey,
      ));
    }

    // Pre-optimize pasted images (decoding uses ui.instantiateImageCodec; PNG encoding uses Isolate.run)
    final Map<String, Uint8List> optimizedImages = {};
    final List<ExportImageDto> imageDtos = [];
    if (knownOrigPageBounds != null && resolvedPdfSizes != null) {
      for (final img in drawingController.images) {
        final origIdx = geom.findOrigPageIndex(knownOrigPageBounds, img.position.dy);
        if (origIdx < 0 || origIdx >= resolvedPdfSizes.length) continue;
        final scaleX = resolvedPdfSizes[origIdx].$1 / knownOrigPageBounds[origIdx].width;
        final scaleY = resolvedPdfSizes[origIdx].$2 / knownOrigPageBounds[origIdx].height;
        final pdfW = roundPdfCoord(img.width * scaleX);
        final pdfH = roundPdfCoord(img.height * scaleY);
        final bucketW = (pdfW / 16.0).ceil() * 16;
        final bucketH = (pdfH / 16.0).ceil() * 16;
        final cacheKey =
            '${PdfImageOptimizer.computeContentKey(img.imageBytes)}|${bucketW}x$bucketH';

        if (!optimizedImages.containsKey(cacheKey)) {
          optimizedImages[cacheKey] = await PdfImageOptimizer.optimizeForPdf(
            img.imageBytes,
            targetPdfWidthPt: pdfW,
            targetPdfHeightPt: pdfH,
          );
        }
        imageDtos.add(ExportImageDto(
          id: img.id,
          posX: img.position.dx,
          posY: img.position.dy,
          width: img.width,
          height: img.height,
          cacheKey: cacheKey,
        ));
      }
    }

    final textAnnDtos = [
      for (final ta in drawingController.textAnnotations)
        ExportTextAnnotationDto(
          id: ta.id,
          type: ta.type,
          rects: [
            for (final r in ta.rects) (r.left, r.top, r.width, r.height),
          ],
          colorArgb: ta.color.toARGB32(),
          pageNumber: ta.pageNumber,
        ),
    ];

    final strokeDtos = [
      for (final s in drawingController.strokes)
        ExportStrokeDto(
          id: s.id,
          points: [
            for (final p in s.points) (p.offset.dx, p.offset.dy, p.pressure),
          ],
          colorArgb: s.color.toARGB32(),
          strokeWidth: s.strokeWidth,
        ),
    ];

    final shapeDtos = [
      for (final sh in drawingController.shapes)
        ExportShapeDto(
          id: sh.id,
          type: sh.type,
          startX: sh.start.dx,
          startY: sh.start.dy,
          endX: sh.end.dx,
          endY: sh.end.dy,
          colorArgb: sh.color.toARGB32(),
          strokeWidth: sh.strokeWidth,
        ),
    ];

    final rawBounds = pageDocBounds
        ?.map((r) => (r.left, r.top, r.width, r.height))
        .toList(growable: false);

    final Map<String, RasterizedBitmapDto?> preRasterizedFallbacks = {};
    final payload = ExportJobPayload(
      baseBytes: baseBytes,
      viewportWidth: viewportWidth,
      textBoxFont: textBoxFont,
      deletedZeroIndexedPages: List<int>.from(deletedZeroIndexedPages),
      addedPagesCount: addedPagesCount,
      pageSpacing: pageSpacing,
      pageDocBounds: rawBounds,
      textAnnotations: textAnnDtos,
      strokes: strokeDtos,
      shapes: shapeDtos,
      textBoxes: textBoxDtos,
      images: imageDtos,
      preRasterizedLatex: preRasterizedLatex,
      preRasterizedFallbacks: preRasterizedFallbacks,
      optimizedImages: optimizedImages,
      embedEditableData: embedEditableData,
    );

    var workerResult = await Isolate.run(() => runPdfExportWorker(payload));

    // Rare fallback path: if any plain text box contained emojis/glyphs unsupported by
    // PDF standard/CJK fonts, rasterize those specific boxes via TextPainter on UI isolate
    // and rerun worker cleanly with fallback bitmaps populated.
    if (workerResult.missingFallbacks.isNotEmpty) {
      for (final req in workerResult.missingFallbacks) {
        if (!preRasterizedFallbacks.containsKey(req.key)) {
          preRasterizedFallbacks[req.key] = await _rasterizeFallbackText(req);
        }
      }
      workerResult = await Isolate.run(() => runPdfExportWorker(payload));
    }

    return workerResult.pdfBytes ?? Uint8List(0);
  }

  static Future<RasterizedBitmapDto?> _rasterizeFallbackText(FallbackRequest req) async {
    const renderScale = 2.0;
    final textColor = Color(req.colorArgb);
    final textPainter = TextPainter(
      text: TextSpan(
        text: req.text,
        style: TextStyle(
          color: textColor,
          fontSize: req.fontSize * renderScale,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    try {
      textPainter.layout(maxWidth: req.maxWidth * renderScale);
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
          final rawBytes = Uint8List.fromList(
            rawData.buffer.asUint8List(
              rawData.offsetInBytes,
              rawData.lengthInBytes,
            ),
          );
          final optPng = await PdfImageOptimizer.encodeOptimizedPngAsync(
            rawStraightRgba: rawBytes,
            width: pWidth,
            height: pHeight,
            logicalSize: Size(pWidth / renderScale, pHeight / renderScale),
            cropTransparentMargins: true,
          );
          if (optPng != null && optPng.bytes.isNotEmpty) {
            return RasterizedBitmapDto(
              bytes: optPng.bytes,
              offsetX: optPng.offset.dx,
              offsetY: optPng.offset.dy,
              width: optPng.size.width,
              height: optPng.size.height,
            );
          }
        }
      } finally {
        img?.dispose();
        picture.dispose();
      }
    } finally {
      textPainter.dispose();
    }
    return null;
  }

  /// Builds exported PDF bytes and atomically writes them to [file].
  /// Inspects PDF bytes in an isolate to detect embedded Advanced editable annotations.
  /// When [prepareCleanBaseForEditable] is true and a valid payload exists, strips
  /// our tagged annotation streams and attachment to return clean base PDF bytes.
  static Future<PdfInspectResult> inspectPdfDocument(
    Uint8List fileBytes, {
    required bool prepareCleanBaseForEditable,
  }) {
    return Isolate.run(() {
      sf.PdfDocument? doc;
      try {
        doc = sf.PdfDocument(inputBytes: fileBytes);
        final gzBytes =
            PdfEditableLayerHelper.extractAnnotationAttachmentBytes(doc);
        if (gzBytes == null) {
          return const PdfInspectResult(hasEditablePayload: false);
        }
        final bundle = AnnotationPersistenceCodec.decodeGzip(gzBytes);
        if (bundle == null || bundle.pageCount != doc.pages.count) {
          return const PdfInspectResult(hasEditablePayload: false);
        }

        Uint8List? cleanBaseBytes;
        if (prepareCleanBaseForEditable) {
          final stripped = PdfEditableLayerHelper.stripAnnotationStreams(doc);
          final removed = PdfEditableLayerHelper.removeAnnotationAttachments(doc);
          if (stripped || removed) {
            doc.compressionLevel = sf.PdfCompressionLevel.best;
            doc.fileStructure.crossReferenceType =
                sf.PdfCrossReferenceType.crossReferenceStream;
            if (fileBytes.length <= 25 * 1024 * 1024) {
              doc.fileStructure.incrementalUpdate = false;
            }
            cleanBaseBytes = Uint8List.fromList(doc.saveAsBytesSync());
          } else {
            cleanBaseBytes = fileBytes;
          }
        }

        return PdfInspectResult(
          hasEditablePayload: true,
          bundle: bundle,
          cleanBaseBytes: cleanBaseBytes,
        );
      } catch (_) {
        return const PdfInspectResult(hasEditablePayload: false);
      } finally {
        doc?.dispose();
      }
    });
  }

  static Future<Uint8List> exportToFile({
    required File file,
    required Uint8List baseBytes,
    required DrawingController drawingController,
    required double viewportWidth,
    required AppFontFamily textBoxFont,
    List<int> deletedZeroIndexedPages = const [],
    int addedPagesCount = 0,
    List<Rect>? pageDocBounds,
    List<Size>? pdfPageSizes,
    bool embedEditableData = false,
  }) async {
    final finalBytes = await buildExportBytes(
      baseBytes: baseBytes,
      drawingController: drawingController,
      viewportWidth: viewportWidth,
      textBoxFont: textBoxFont,
      deletedZeroIndexedPages: deletedZeroIndexedPages,
      addedPagesCount: addedPagesCount,
      pageDocBounds: pageDocBounds,
      pdfPageSizes: pdfPageSizes,
      embedEditableData: embedEditableData,
    );
    await atomicWriteBytes(file, finalBytes);
    return finalBytes;
  }
}

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../controllers/drawing_controller.dart';
import '../models/editor_models.dart';
import 'editor_settings_service.dart';

class PdfExportService {
  PdfExportService._();

  static sf.PdfColor _toPdfColor(Color c) {
    return sf.PdfColor(
      (c.r * 255.0).round().clamp(0, 255),
      (c.g * 255.0).round().clamp(0, 255),
      (c.b * 255.0).round().clamp(0, 255),
      (c.a * 255.0).round().clamp(0, 255),
    );
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
  static Future<void> atomicWriteString(File targetFile, String content) async {
    final parent = targetFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final tempPath = '${targetFile.path}.tmp.${DateTime.now().microsecondsSinceEpoch}';
    final tempFile = File(tempPath);
    try {
      await tempFile.writeAsString(content, flush: true);
      try {
        await tempFile.rename(targetFile.path);
      } on FileSystemException {
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
    final doc = sf.PdfDocument(inputBytes: Uint8List.fromList(baseBytes));
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

      // 5. Render text annotations (highlights, underlines, strikethroughs)
      for (final ta in drawingController.textAnnotations) {
        final origIdx = ta.pageNumber - 1;
        if (origIdx < 0 || origIdx >= origPageCount) continue;
        final newIdx = oldToNewPageIdx[origIdx];
        if (newIdx < 0 || newIdx >= doc.pages.count) continue;

        final page = doc.pages[newIdx];
        final bounds = origPageBounds[origIdx];
        final scaleX = page.size.width / bounds.width;
        final scaleY = page.size.height / bounds.height;

        if (ta.type == TextAnnotationType.highlight) {
          page.graphics.save();
          page.graphics.setTransparency(0.35, mode: sf.PdfBlendMode.multiply);
          final brush = sf.PdfSolidBrush(_toPdfColor(ta.color));
          for (final r in ta.rects) {
            final pdfRect = Rect.fromLTWH(
              (r.left - bounds.left) * scaleX,
              (r.top - bounds.top) * scaleY,
              r.width * scaleX,
              r.height * scaleY,
            );
            page.graphics.drawRectangle(bounds: pdfRect, brush: brush);
          }
          page.graphics.restore();
        } else if (ta.type == TextAnnotationType.underline) {
          final pen = sf.PdfPen(_toPdfColor(ta.color), width: 1.5 * scaleX);
          for (final r in ta.rects) {
            final y = (r.bottom - bounds.top) * scaleY;
            page.graphics.drawLine(
              pen,
              Offset((r.left - bounds.left) * scaleX, y),
              Offset((r.right - bounds.left) * scaleX, y),
            );
          }
        } else if (ta.type == TextAnnotationType.strikethrough) {
          final pen = sf.PdfPen(_toPdfColor(ta.color), width: 1.5 * scaleX);
          for (final r in ta.rects) {
            final y = (r.center.dy - bounds.top) * scaleY;
            page.graphics.drawLine(
              pen,
              Offset((r.left - bounds.left) * scaleX, y),
              Offset((r.right - bounds.left) * scaleX, y),
            );
          }
        }
      }

      // 6. Draw strokes efficiently using connected path and point deduplication
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
          final pt = Offset(
            (stroke.points.first.offset.dx - bounds.left) * scaleX,
            (stroke.points.first.offset.dy - bounds.top) * scaleY,
          );
          final r = math.max(0.5, (stroke.strokeWidth * stroke.points.first.pressure / 2.0) * scaleX);
          final brush = sf.PdfSolidBrush(_toPdfColor(stroke.color));
          page.graphics.drawEllipse(Rect.fromCircle(center: pt, radius: r), brush: brush);
        } else {
          final List<Offset> docPoints = [];
          Offset? lastPt;
          for (final p in stroke.points) {
            final pt = Offset(
              (p.offset.dx - bounds.left) * scaleX,
              (p.offset.dy - bounds.top) * scaleY,
            );
            if (lastPt == null || (pt - lastPt).distanceSquared > 0.25) {
              docPoints.add(pt);
              lastPt = pt;
            }
          }
          if (docPoints.length < 2) {
            if (docPoints.isNotEmpty) {
              final r = math.max(0.5, (stroke.strokeWidth / 2.0) * scaleX);
              final brush = sf.PdfSolidBrush(_toPdfColor(stroke.color));
              page.graphics.drawEllipse(
                Rect.fromCircle(center: docPoints.first, radius: r),
                brush: brush,
              );
            }
            continue;
          }

          final pen = sf.PdfPen(
            _toPdfColor(stroke.color),
            width: math.max(0.5, stroke.strokeWidth * scaleX),
          );
          pen.lineCap = sf.PdfLineCap.round;
          pen.lineJoin = sf.PdfLineJoin.round;

          final path = sf.PdfPath();
          for (int i = 0; i < docPoints.length - 1; i++) {
            path.addLine(docPoints[i], docPoints[i + 1]);
          }
          page.graphics.drawPath(path, pen: pen);
        }
      }

      // 7. Draw geometric shapes
      for (final shape in drawingController.shapes) {
        final origIdx = findOrigPageIndex(shape.start.dy);
        if (origIdx < 0 || origIdx >= origPageCount) continue;
        final newIdx = oldToNewPageIdx[origIdx];
        if (newIdx < 0 || newIdx >= doc.pages.count) continue;

        final page = doc.pages[newIdx];
        final bounds = origPageBounds[origIdx];
        final scaleX = page.size.width / bounds.width;
        final scaleY = page.size.height / bounds.height;

        final start = Offset(
          (shape.start.dx - bounds.left) * scaleX,
          (shape.start.dy - bounds.top) * scaleY,
        );
        final end = Offset(
          (shape.end.dx - bounds.left) * scaleX,
          (shape.end.dy - bounds.top) * scaleY,
        );
        final pen = sf.PdfPen(
          _toPdfColor(shape.color),
          width: shape.strokeWidth * scaleX,
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
            page.graphics.drawLine(pen, start, end);
            final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
            final arrowLength = math.max(shape.strokeWidth * 4.0 * scaleX, 12.0);
            const arrowAngle = math.pi / 6;

            final p1 = Offset(
              end.dx - arrowLength * math.cos(angle - arrowAngle),
              end.dy - arrowLength * math.sin(angle - arrowAngle),
            );
            final p2 = Offset(
              end.dx - arrowLength * math.cos(angle + arrowAngle),
              end.dy - arrowLength * math.sin(angle + arrowAngle),
            );

            page.graphics.drawLine(pen, end, p1);
            page.graphics.drawLine(pen, end, p2);
            break;
        }
      }

      // 8. Draw text boxes (native vector text with auto-wrapping, fallback to raster for emojis)
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

        final pos = Offset(
          ((tb.position.dx - bounds.left) + 4) * scaleX,
          (tb.position.dy + 2 - bounds.top) * scaleY,
        );
        final tbWidth = (tb.width ?? 220.0) * scaleX;

        final isPureAscii = tb.text.codeUnits.every(
          (c) => (c >= 32 && c < 127) || c == 10 || c == 13 || c == 9,
        );

        sf.PdfFont font;
        if (isPureAscii) {
          switch (textBoxFont) {
            case AppFontFamily.sansSerif:
              font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, tb.fontSize * scaleX);
              break;
            case AppFontFamily.serif:
              font = sf.PdfStandardFont(sf.PdfFontFamily.timesRoman, tb.fontSize * scaleX);
              break;
            case AppFontFamily.monospace:
              font = sf.PdfStandardFont(sf.PdfFontFamily.courier, tb.fontSize * scaleX);
              break;
          }
        } else if (RegExp(r'[\u3040-\u30ff]').hasMatch(tb.text)) {
          font = sf.PdfCjkStandardFont(
            textBoxFont == AppFontFamily.serif
                ? sf.PdfCjkFontFamily.heiseiMinchoW3
                : sf.PdfCjkFontFamily.heiseiKakuGothicW5,
            tb.fontSize * scaleX,
          );
        } else if (RegExp(r'[\uac00-\ud7af]').hasMatch(tb.text)) {
          font = sf.PdfCjkStandardFont(
            textBoxFont == AppFontFamily.serif
                ? sf.PdfCjkFontFamily.hanyangSystemsShinMyeongJoMedium
                : sf.PdfCjkFontFamily.hanyangSystemsGothicMedium,
            tb.fontSize * scaleX,
          );
        } else {
          font = sf.PdfCjkStandardFont(
            sf.PdfCjkFontFamily.sinoTypeSongLight,
            tb.fontSize * scaleX,
          );
        }

        final brush = sf.PdfSolidBrush(_toPdfColor(tb.color));
        final format = sf.PdfStringFormat(
          wordWrap: sf.PdfWordWrapType.word,
        );

        try {
          page.graphics.drawString(
            tb.text,
            font,
            bounds: Rect.fromLTWH(
              pos.dx,
              pos.dy,
              tbWidth,
              1000 * scaleY,
            ),
            brush: brush,
            format: format,
          );
        } catch (_) {
          const renderScale = 2.0;
          final textPainter = TextPainter(
            text: TextSpan(
              text: tb.text,
              style: TextStyle(
                color: tb.color,
                fontSize: tb.fontSize * scaleX * renderScale,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout(maxWidth: tbWidth * renderScale);

          final pWidth = math.max(1, textPainter.width.ceil());
          final pHeight = math.max(1, textPainter.height.ceil());

          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          textPainter.paint(canvas, Offset.zero);

          final picture = recorder.endRecording();
          final img = await picture.toImage(pWidth, pHeight);
          final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
          picture.dispose();
          img.dispose();

          if (byteData != null) {
            final pngBytes = byteData.buffer.asUint8List();
            final bmp = sf.PdfBitmap(pngBytes);
            page.graphics.drawImage(
              bmp,
              Rect.fromLTWH(
                pos.dx,
                pos.dy,
                pWidth / renderScale,
                pHeight / renderScale,
              ),
            );
          }
        }
      }

      // 9. Draw pasted images
      for (final img in drawingController.images) {
        final origIdx = findOrigPageIndex(img.position.dy);
        if (origIdx < 0 || origIdx >= origPageCount) continue;
        final newIdx = oldToNewPageIdx[origIdx];
        if (newIdx < 0 || newIdx >= doc.pages.count) continue;

        final page = doc.pages[newIdx];
        final bounds = origPageBounds[origIdx];
        final scaleX = page.size.width / bounds.width;
        final scaleY = page.size.height / bounds.height;

        final pos = Offset(
          (img.position.dx - bounds.left) * scaleX,
          (img.position.dy - bounds.top) * scaleY,
        );
        final bmp = sf.PdfBitmap(img.imageBytes);
        page.graphics.drawImage(
          bmp,
          Rect.fromLTWH(pos.dx, pos.dy, img.width * scaleX, img.height * scaleY),
        );
      }

      return Uint8List.fromList(doc.saveSync());
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


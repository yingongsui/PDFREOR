import 'dart:io' show ZLibCodec;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/controllers/drawing_controller.dart';
import 'package:pdfreor/models/editor_models.dart';
import 'package:pdfreor/services/editor_settings_service.dart';
import 'package:pdfreor/services/pdf_export_service.dart';
import 'package:pdfreor/services/pdf_image_optimizer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

Uint8List _encodeRawRgbaPng(Uint8List rawRgba, int width, int height) {
  final crcTable = Uint32List(256);
  for (int n = 0; n < 256; n++) {
    int c = n;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    crcTable[n] = c;
  }

  void writeChunk(BytesBuilder out, List<int> type, List<int> data) {
    final len = data.length;
    out.add(<int>[(len >>> 24) & 0xFF, (len >>> 16) & 0xFF, (len >>> 8) & 0xFF, len & 0xFF]);
    out.add(type);
    out.add(data);
    int crc = 0xFFFFFFFF;
    for (final b in type) {
      crc = crcTable[(crc ^ b) & 0xFF] ^ (crc >>> 8);
    }
    for (final b in data) {
      crc = crcTable[(crc ^ b) & 0xFF] ^ (crc >>> 8);
    }
    crc = (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
    out.add(<int>[(crc >>> 24) & 0xFF, (crc >>> 16) & 0xFF, (crc >>> 8) & 0xFF, crc & 0xFF]);
  }

  final stride = 1 + width * 4;
  final scanlines = Uint8List(height * stride);
  for (int y = 0; y < height; y++) {
    scanlines[y * stride] = 0;
    final srcStart = y * width * 4;
    scanlines.setRange(y * stride + 1, (y + 1) * stride, rawRgba, srcStart);
  }
  final idat = ZLibCodec(level: 6).encode(scanlines);
  final ihdr = <int>[
    (width >>> 24) & 0xFF, (width >>> 16) & 0xFF, (width >>> 8) & 0xFF, width & 0xFF,
    (height >>> 24) & 0xFF, (height >>> 16) & 0xFF, (height >>> 8) & 0xFF, height & 0xFF,
    8, 6, 0, 0, 0,
  ];
  final out = BytesBuilder(copy: false);
  out.add(const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  writeChunk(out, const <int>[73, 72, 68, 82], ihdr);
  writeChunk(out, const <int>[73, 68, 65, 84], idat);
  writeChunk(out, const <int>[73, 69, 78, 68], const <int>[]);
  return out.takeBytes();
}

Uint8List _createBlankPdfBytes({int pageCount = 1}) {
  final doc = sf.PdfDocument();
  doc.pageSettings.margins.all = 0;
  for (int i = 0; i < pageCount; i++) {
    doc.pages.add();
  }
  final bytes = doc.saveAsBytesSync();
  doc.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDF Export Size Optimizations', () {
    test('Optimization 1: Opaque RGBA screenshot strips alpha, downsamples to ~220 DPI, and deduplicates', () async {
      const int srcW = 640;
      const int srcH = 480;
      final rawRgba = Uint8List(srcW * srcH * 4);
      int state = 0x12345678;
      for (int y = 0; y < srcH; y++) {
        for (int x = 0; x < srcW; x++) {
          state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
          final idx = (y * srcW + x) * 4;
          // Smooth gradient + subtle texture so PNG predictors shine and data isn't trivial
          rawRgba[idx] = ((x * 255 ~/ srcW) ^ (state & 0x0F)) & 0xFF;
          rawRgba[idx + 1] = ((y * 255 ~/ srcH) ^ ((state >>> 4) & 0x0F)) & 0xFF;
          rawRgba[idx + 2] = (((x + y) * 127 ~/ (srcW + srcH)) ^ ((state >>> 8) & 0x0F)) & 0xFF;
          rawRgba[idx + 3] = 255; // Fully opaque screenshot
        }
      }

      final unoptimizedRgbaPng = _encodeRawRgbaPng(rawRgba, srcW, srcH);
      final headerBefore = PdfImageOptimizer.readImageHeader(unoptimizedRgbaPng);
      expect(headerBefore, isNotNull);
      expect(headerBefore!.isPng, isTrue);
      expect(headerBefore.pngColorType, 6);

      // Baseline: directly embedding raw colorType=6 RGBA PNG into Syncfusion PDF
      final baselineDoc = sf.PdfDocument();
      baselineDoc.compressionLevel = sf.PdfCompressionLevel.best;
      final basePage = baselineDoc.pages.add();
      basePage.graphics.drawImage(
        sf.PdfBitmap(unoptimizedRgbaPng),
        const Rect.fromLTWH(40, 40, 120, 90),
      );
      final baselinePdfBytes = baselineDoc.saveAsBytesSync();
      baselineDoc.dispose();

      // Optimized export via PdfExportService at 120x90 pt (target ~367x275 px, opaque RGB colorType=2)
      final baseBlank = _createBlankPdfBytes();
      final singleCtrl = DrawingController();
      addTearDown(singleCtrl.dispose);
      singleCtrl.addImage(DrawnImage(
        id: 'img_1',
        imageBytes: unoptimizedRgbaPng,
        position: const Offset(40, 40),
        width: 120,
        height: 90,
        pageNumber: 1,
      ));

      final optSinglePdf = await PdfExportService.buildExportBytes(
        baseBytes: baseBlank,
        drawingController: singleCtrl,
        viewportWidth: 595.0,
        textBoxFont: AppFontFamily.sansSerif,
      );

      // Optimized PDF should be dramatically smaller than naive RGBA XObject + SMask
      expect(optSinglePdf.length, lessThan((baselinePdfBytes.length * 0.45).round()));

      // Deduplication check: pasting the same image 4 times reuses 1 XObject
      final multiCtrl = DrawingController();
      addTearDown(multiCtrl.dispose);
      for (int i = 0; i < 4; i++) {
        multiCtrl.addImage(DrawnImage(
          id: 'img_$i',
          imageBytes: unoptimizedRgbaPng,
          position: Offset(40.0 + i * 20.0, 40.0 + i * 30.0),
          width: 120,
          height: 90,
          pageNumber: 1,
        ));
      }

      final optMultiPdf = await PdfExportService.buildExportBytes(
        baseBytes: baseBlank,
        drawingController: multiCtrl,
        viewportWidth: 595.0,
        textBoxFont: AppFontFamily.sansSerif,
      );

      final extraBytesFor3Copies = optMultiPdf.length - optSinglePdf.length;
      expect(extraBytesFor3Copies, lessThan(350));
    });

    test('Optimization 2: RDP stroke simplification preserves corners and batches same-style strokes', () async {
      // 200-point near-collinear horizontal stroke + sharp 90-degree vertical turn
      final rawLPoints = <Offset>[
        for (int i = 0; i <= 100; i++) Offset(20.0 + i * 1.5, 50.0 + (i.isEven ? 0.08 : -0.08)),
        for (int i = 1; i <= 100; i++) Offset(170.0 + (i.isEven ? 0.06 : -0.06), 50.0 + i * 1.2),
      ];
      final simplified = PdfExportService.simplifyStrokePoints(rawLPoints, epsilon: 0.25);
      // Should collapse ~201 dense points down to 3 key vertices: start, corner, end
      expect(simplified.length, lessThanOrEqualTo(4));
      expect(simplified.first, const Offset(20.0, 50.1));
      expect(simplified.last.dx, closeTo(170.0, 0.2));
      expect(simplified.last.dy, closeTo(170.0, 0.2));

      // Compare naive unbatched 40 dense strokes vs optimized buildExportBytes
      final baseBlank = _createBlankPdfBytes();
      final ctrl = DrawingController();
      addTearDown(ctrl.dispose);

      final naiveDoc = sf.PdfDocument(inputBytes: baseBlank);
      naiveDoc.compressionLevel = sf.PdfCompressionLevel.best;
      final naivePage = naiveDoc.pages[0];

      for (int s = 0; s < 40; s++) {
        final pts = <StrokePoint>[
          for (int i = 0; i < 60; i++)
            StrokePoint(
              offset: Offset(30.0 + i * 3.123456, 40.0 + s * 10.0 + (i % 3) * 0.05),
              pressure: 0.6,
            ),
        ];
        ctrl.startStroke(pts.first.offset, pts.first.pressure);
        for (int i = 1; i < pts.length; i++) {
          ctrl.addStrokePoint(pts[i].offset, pts[i].pressure);
        }
        ctrl.endStroke(Colors.blue, 2.0, 1);

        final pen = sf.PdfPen(sf.PdfColor(33, 150, 243), width: 2.0)
          ..lineCap = sf.PdfLineCap.round
          ..lineJoin = sf.PdfLineJoin.round;
        for (int i = 0; i < pts.length - 1; i++) {
          naivePage.graphics.drawLine(pen, pts[i].offset, pts[i + 1].offset);
        }
      }
      final naiveStrokePdf = naiveDoc.saveAsBytesSync();
      naiveDoc.dispose();

      // Also include a single-point dot to verify dot flushing works alongside batched paths
      ctrl.startStroke(const Offset(100, 500), 0.8);
      ctrl.endStroke(Colors.red, 3.0, 1);

      final optStrokePdf = await PdfExportService.buildExportBytes(
        baseBytes: baseBlank,
        drawingController: ctrl,
        viewportWidth: 595.0,
        textBoxFont: AppFontFamily.sansSerif,
      );

      expect(optStrokePdf.length, lessThan((naiveStrokePdf.length * 0.5).round()));
    });

    test('Optimization 3: Deleting a heavy page disables incrementalUpdate and garbage-collects resources', () async {
      // Build a 3-page PDF where Page 2 holds a heavy pseudo-random image (> 80 KB)
      const int imgW = 300;
      const int imgH = 300;
      final noisyRgba = Uint8List(imgW * imgH * 4);
      int rng = 0xCAFEBABE;
      for (int i = 0; i < noisyRgba.length; i += 4) {
        rng = (rng * 1664525 + 1013904223) & 0xFFFFFFFF;
        noisyRgba[i] = rng & 0xFF;
        noisyRgba[i + 1] = (rng >>> 8) & 0xFF;
        noisyRgba[i + 2] = (rng >>> 16) & 0xFF;
        noisyRgba[i + 3] = 255;
      }
      final heavyPng = PdfImageOptimizer.encodeOptimizedPngFromRgba(
        rawStraightRgba: noisyRgba,
        width: imgW,
        height: imgH,
        logicalSize: const Size(300, 300),
      )!;

      final srcDoc = sf.PdfDocument();
      srcDoc.compressionLevel = sf.PdfCompressionLevel.best;
      final p1 = srcDoc.pages.add();
      p1.graphics.drawString(
        'Page 1 kept',
        sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 14),
        bounds: const Rect.fromLTWH(20, 20, 200, 40),
      );
      final p2 = srcDoc.pages.add();
      p2.graphics.drawImage(sf.PdfBitmap(heavyPng.bytes), const Rect.fromLTWH(20, 20, 300, 300));
      final p3 = srcDoc.pages.add();
      p3.graphics.drawString(
        'Page 3 kept',
        sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 14),
        bounds: const Rect.fromLTWH(20, 20, 200, 40),
      );
      final threePageBytes = srcDoc.saveAsBytesSync();
      srcDoc.dispose();

      expect(threePageBytes.length, greaterThan(150 * 1024));

      final ctrl = DrawingController();
      addTearDown(ctrl.dispose);

      // Delete Page 2 (zero-indexed page 1)
      final afterDeleteBytes = await PdfExportService.buildExportBytes(
        baseBytes: threePageBytes,
        drawingController: ctrl,
        viewportWidth: 595.0,
        textBoxFont: AppFontFamily.sansSerif,
        deletedZeroIndexedPages: const <int>[1],
      );

      // Deleted page's heavy image stream must be physically reclaimed!
      expect(afterDeleteBytes.length, lessThan(25 * 1024));

      final verifyDoc = sf.PdfDocument(inputBytes: afterDeleteBytes);
      expect(verifyDoc.pages.count, 2);
      verifyDoc.dispose();
    });

    test('Optimization 4: Collinear highlight/underline rects merge per line and export cleanly', () async {
      final wordRects = <Rect>[
        // Line 1: 8 adjacent/slightly-gapped word boxes
        for (int i = 0; i < 8; i++)
          Rect.fromLTWH(40.0 + i * 32.0, 100.0 + (i.isEven ? 0.2 : -0.2), 30.5, 14.0),
        // Line 2: 6 overlapping/adjacent word boxes
        for (int i = 0; i < 6; i++)
          Rect.fromLTWH(40.0 + i * 35.0, 122.0, 36.0, 14.0),
      ];

      final merged = PdfExportService.mergeCollinearRects(wordRects);
      expect(merged.length, 2);
      expect(merged[0].left, closeTo(40.0, 0.2));
      expect(merged[0].right, closeTo(40.0 + 7 * 32.0 + 30.5, 0.2));
      expect(merged[1].left, closeTo(40.0, 0.2));
      expect(merged[1].right, closeTo(40.0 + 5 * 35.0 + 36.0, 0.2));

      final baseBlank = _createBlankPdfBytes();
      final ctrl = DrawingController();
      addTearDown(ctrl.dispose);
      for (int k = 0; k < 5; k++) {
        ctrl.addTextAnnotation(DrawnTextAnnotation(
          id: 'hl_$k',
          pageNumber: 1,
          rects: <Rect>[
            for (int w = 0; w < 6; w++)
              Rect.fromLTWH(30.0 + w * 28.0, 60.0 + k * 24.0, 27.0, 13.0),
          ],
          color: Colors.yellow,
          type: TextAnnotationType.highlight,
        ));
      }
      ctrl.addTextAnnotation(DrawnTextAnnotation(
        id: 'ul_1',
        pageNumber: 1,
        rects: wordRects,
        color: Colors.red,
        type: TextAnnotationType.underline,
      ));

      final exported = await PdfExportService.buildExportBytes(
        baseBytes: baseBlank,
        drawingController: ctrl,
        viewportWidth: 595.0,
        textBoxFont: AppFontFamily.sansSerif,
      );

      final verifyDoc = sf.PdfDocument(inputBytes: exported);
      expect(verifyDoc.pages.count, 1);
      verifyDoc.dispose();
    });

    test('Optimization 5: PdfFont caching reuses font dictionaries across multiple CJK and ASCII text boxes', () async {
      final baseBlank = _createBlankPdfBytes();
      final singleCtrl = DrawingController();
      final manyCtrl = DrawingController();
      addTearDown(singleCtrl.dispose);
      addTearDown(manyCtrl.dispose);

      // Unicode escape for CJK sample text so source stays pure ASCII
      const cjkSample = '\u7b14\u8bb0\u6d4b\u8bd5 Note 1';

      singleCtrl.addTextBox(DrawnTextBox(
        id: 'tb_single',
        text: cjkSample,
        position: const Offset(40, 40),
        color: Colors.black,
        fontSize: 16.0,
        pageNumber: 1,
      ));

      for (int i = 0; i < 20; i++) {
        manyCtrl.addTextBox(DrawnTextBox(
          id: 'tb_$i',
          text: '\u7b14\u8bb0\u6d4b\u8bd5 Note $i',
          position: Offset(40.0, 30.0 + i * 24.0),
          color: Colors.black,
          fontSize: 16.0,
          pageNumber: 1,
        ));
      }

      final singlePdf = await PdfExportService.buildExportBytes(
        baseBytes: baseBlank,
        drawingController: singleCtrl,
        viewportWidth: 595.0,
        textBoxFont: AppFontFamily.sansSerif,
      );
      final manyPdf = await PdfExportService.buildExportBytes(
        baseBytes: baseBlank,
        drawingController: manyCtrl,
        viewportWidth: 595.0,
        textBoxFont: AppFontFamily.sansSerif,
      );

      // 19 extra CJK text boxes reusing 1 cached PdfCjkStandardFont add tiny stream overhead (< 1.5 KB)
      expect(manyPdf.length - singlePdf.length, lessThan(1500));

      final verifyDoc = sf.PdfDocument(inputBytes: manyPdf);
      final extracted = sf.PdfTextExtractor(verifyDoc).extractText();
      verifyDoc.dispose();
      expect(extracted, contains('Note 0'));
      expect(extracted, contains('Note 19'));
    });
  });
}

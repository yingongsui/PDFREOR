import 'dart:io' show ZLibCodec;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/controllers/drawing_controller.dart';
import 'package:pdfreor/models/editor_models.dart';
import 'package:pdfreor/services/editor_settings_service.dart';
import 'package:pdfreor/services/latex_rasterizer.dart';
import 'package:pdfreor/services/pdf_export_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

Uint8List _encodeNaiveRgbaPng(Uint8List rawRgba, int width, int height) {
  // Build standard uncropped colorType=6 RGBA PNG for baseline PDF size comparison
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
  final idat = ZLibCodec(level: 9).encode(scanlines);
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

void main() {
  group('LaTeX Box Tests', () {
    test('Add LaTeX Box, update text and layout position, and undo', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      final latexBox = DrawnTextBox(
        id: 'latex_1',
        text: r'\frac{a}{b}',
        position: const Offset(50, 100),
        color: Colors.red,
        fontSize: 18.0,
        pageNumber: 1,
        width: 180.0,
        isLatex: true,
      );

      controller.addTextBox(latexBox);
      expect(controller.textBoxes.length, 1);
      expect(controller.textBoxes.first.isLatex, true);
      expect(controller.textBoxes.first.text, r'\frac{a}{b}');

      // Update LaTeX content and move position
      latexBox.text = r'\int_0^\infty e^{-x^2} dx';
      latexBox.position = const Offset(120, 240);
      controller.updateTextBox(latexBox);
      controller.recordTextBoxLayoutModification(latexBox, const Offset(50, 100), 180.0);
      expect(controller.textBoxes.first.text, r'\int_0^\infty e^{-x^2} dx');
      expect(controller.textBoxes.first.position, const Offset(120, 240));

      // Undo layout move
      controller.undo();
      expect(controller.textBoxes.first.position, const Offset(50, 100));

      // Undo addition
      controller.undo();
      expect(controller.textBoxes.isEmpty, true);
    });

    test('computeTargetPixelRatio scales to ~200 PDF DPI and clamps safely', () {
      // Landscape tablet (1100px viewport on 595.28pt A4 -> scaleX ~ 0.541)
      final landscapeRatio = LatexRasterizer.computeTargetPixelRatio(595.28 / 1100.0);
      expect(landscapeRatio, closeTo(1.50, 0.05));

      // Portrait tablet (800px viewport on 595.28pt A4 -> scaleX ~ 0.744)
      final portraitRatio = LatexRasterizer.computeTargetPixelRatio(595.28 / 800.0);
      expect(portraitRatio, closeTo(2.05, 0.05));

      // Extreme low and high scale clamping
      expect(LatexRasterizer.computeTargetPixelRatio(0.2), 1.25);
      expect(LatexRasterizer.computeTargetPixelRatio(2.0), 2.50);
      expect(LatexRasterizer.computeTargetPixelRatio(0.0), 2.0);
    });

    test('encodeCompactLatexPng crops margins, uses Grayscale+Alpha or constant RGB, and shrinks PDF size', () {
      const int width = 360;
      const int height = 120;
      const logicalSize = Size(180, 60);
      final rawRgba = Uint8List(width * height * 4);

      // Simulate anti-aliased strokes inside [40..310, 30..85] with noisy RGB edge jitter
      for (int y = 30; y <= 85; y++) {
        for (int x = 40; x <= 310; x++) {
          final bool onStroke = ((x + y) % 11 < 4) || (y == 57);
          if (!onStroke) continue;
          final int alpha = ((x * 37 + y * 53) % 240) + 16;
          final int idx = (y * width + x) * 4;
          // Simulate unpremultiplied edge rounding jitter around charcoal (0x21)
          rawRgba[idx] = 32 + (x % 3);
          rawRgba[idx + 1] = 32 + (y % 3);
          rawRgba[idx + 2] = 33;
          rawRgba[idx + 3] = alpha;
        }
      }

      // 1. Monochrome formula (#212121) -> PNG colorType 4 (Grayscale + Alpha)
      final grayRes = LatexRasterizer.encodeCompactLatexPng(
        rawRgba: rawRgba,
        width: width,
        height: height,
        logicalSize: logicalSize,
        color: const Color(0xFF212121),
      );
      expect(grayRes, isNotNull);
      // PNG IHDR colorType sits at byte index 25 (8 sig + 4 len + 4 'IHDR' + 8 w/h + 1 depth)
      expect(grayRes!.bytes[25], 4);
      // Cropped bounds [39..311, 29..86] -> 273x58 px -> logical offset (19.5, 14.5), size (136.5, 29.0)
      expect(grayRes.offset.dx, closeTo(19.5, 0.01));
      expect(grayRes.offset.dy, closeTo(14.5, 0.01));
      expect(grayRes.size.width, closeTo(136.5, 0.01));
      expect(grayRes.size.height, closeTo(29.0, 0.01));

      // 2. Colored formula (#D32F2F) -> PNG colorType 6 (constant RGB + Alpha)
      final redRes = LatexRasterizer.encodeCompactLatexPng(
        rawRgba: rawRgba,
        width: width,
        height: height,
        logicalSize: logicalSize,
        color: const Color(0xFFD32F2F),
      );
      expect(redRes, isNotNull);
      expect(redRes!.bytes[25], 6);

      // 3. Compare actual Syncfusion PDF stream size: naive RGBA vs compact monochrome
      int measurePdfWithImage(Uint8List pngBytes) {
        final doc = sf.PdfDocument();
        doc.compressionLevel = sf.PdfCompressionLevel.best;
        final page = doc.pages.add();
        page.graphics.drawImage(sf.PdfBitmap(pngBytes), const Rect.fromLTWH(20, 20, 140, 30));
        final saved = doc.saveSync();
        doc.dispose();
        return saved.length;
      }

      final naivePng = _encodeNaiveRgbaPng(rawRgba, width, height);
      final naivePdfLen = measurePdfWithImage(naivePng);
      final compactGrayPdfLen = measurePdfWithImage(grayRes.bytes);
      final compactRedPdfLen = measurePdfWithImage(redRes.bytes);

      // Both monochrome and colored compact encodings must substantially shrink PDF output
      expect(compactGrayPdfLen, lessThan((naivePdfLen * 0.65).round()));
      expect(compactRedPdfLen, lessThan((naivePdfLen * 0.70).round()));

      // 4. Fully transparent buffer returns null
      final emptyRes = LatexRasterizer.encodeCompactLatexPng(
        rawRgba: Uint8List(40 * 20 * 4),
        width: 40,
        height: 20,
        logicalSize: const Size(20, 10),
        color: Colors.black,
      );
      expect(emptyRes, isNull);
    });

    testWidgets('End-to-end LaTeX export deduplicates identical formulas in PDF', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      await tester.runAsync(() async {
        final baseDoc = sf.PdfDocument();
        baseDoc.pageSettings.margins.all = 0;
        baseDoc.pageSettings.size = const Size(595, 842);
        baseDoc.pages.add();
        final baseBytes = Uint8List.fromList(baseDoc.saveSync());
        baseDoc.dispose();

        // Verify direct rasterizer produces a non-empty cropped compact PNG
        final directRaster = await LatexRasterizer.rasterize(
          latex: r'\int_{0}^{\infty} \frac{\sin(x)}{x} dx = \frac{\pi}{2}',
          fontSize: 20.0,
          color: const Color(0xFF212121),
          pixelRatio: 1.65,
        );
        expect(directRaster, isNotNull);
        expect(directRaster!.bytes, isNotEmpty);

        // Baseline export with 0 formulas (normalizes cross-reference stream compression)
        final emptyCtrl = DrawingController();
        final baselineExportBytes = await PdfExportService.buildExportBytes(
          baseBytes: baseBytes,
          drawingController: emptyCtrl,
          viewportWidth: 1000.0,
          textBoxFont: AppFontFamily.sansSerif,
        );
        emptyCtrl.dispose();

        // Export with 1 formula on a 1000px tablet viewport
        final singleCtrl = DrawingController();
        singleCtrl.addTextBox(DrawnTextBox(
          id: 'eq_1',
          text: r'\int_{0}^{\infty} \frac{\sin(x)}{x} dx = \frac{\pi}{2}',
          position: const Offset(80, 120),
          color: const Color(0xFF212121),
          fontSize: 20.0,
          pageNumber: 1,
          isLatex: true,
        ));

        final singlePdfBytes = await PdfExportService.buildExportBytes(
          baseBytes: baseBytes,
          drawingController: singleCtrl,
          viewportWidth: 1000.0,
          textBoxFont: AppFontFamily.sansSerif,
        );
        singleCtrl.dispose();

        // Export with 5 identical formulas on the same page
        final multiCtrl = DrawingController();
        for (int i = 0; i < 5; i++) {
          multiCtrl.addTextBox(DrawnTextBox(
            id: 'eq_$i',
            text: r'\int_{0}^{\infty} \frac{\sin(x)}{x} dx = \frac{\pi}{2}',
            position: Offset(80, 120.0 + i * 90.0),
            color: const Color(0xFF212121),
            fontSize: 20.0,
            pageNumber: 1,
            isLatex: true,
          ));
        }

        final multiPdfBytes = await PdfExportService.buildExportBytes(
          baseBytes: baseBytes,
          drawingController: multiCtrl,
          viewportWidth: 1000.0,
          textBoxFont: AppFontFamily.sansSerif,
        );
        multiCtrl.dispose();

        // Verify exported PDFs are valid
        final verifyDoc = sf.PdfDocument(inputBytes: multiPdfBytes);
        expect(verifyDoc.pages.count, 1);
        verifyDoc.dispose();

        final singleFormulaOverhead = singlePdfBytes.length - baselineExportBytes.length;
        final fourExtraCopiesOverhead = multiPdfBytes.length - singlePdfBytes.length;

        // Single formula overhead should be compact (only a few KB)
        expect(singleFormulaOverhead, greaterThan(200));
        expect(singleFormulaOverhead, lessThan(8000));

        // 4 extra copies reuse the exact same PdfBitmap XObject (< 400 bytes total for 4 draw ops)
        expect(fourExtraCopiesOverhead, lessThan(400));
      });
    });
  });
}

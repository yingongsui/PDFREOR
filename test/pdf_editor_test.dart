import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/controllers/drawing_controller.dart';
import 'package:pdfreor/models/editor_models.dart';
import 'package:pdfreor/services/editor_settings_service.dart';
import 'package:pdfreor/services/pdf_export_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  test('PdfDocument shape and arrow drawing', () {
    final doc = PdfDocument();
    final page = doc.pages.add();

    final start = const Offset(50, 50);
    final end = const Offset(150, 150);
    final pen = PdfPen(PdfColor(255, 0, 0), width: 3);

    page.graphics.drawLine(pen, start, end);

    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    const arrowLength = 15.0;
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

    final bytes = doc.saveSync();
    doc.dispose();
    expect(bytes.isNotEmpty, true);
  });

  test('PdfExportService remaps annotations accurately when pages are deleted and writes atomically', () async {
    // Build a 3-page base PDF (each default page is 515x762 or 595x842)
    final srcDoc = PdfDocument();
    final p0 = srcDoc.pages.add();
    srcDoc.pages.add();
    srcDoc.pages.add();
    final pageWidth = p0.size.width;
    final pageHeight = p0.size.height;
    final baseBytes = Uint8List.fromList(srcDoc.saveSync());
    srcDoc.dispose();

    const viewportWidth = 400.0;
    const pageSpacing = 4.0;
    final renderedH = viewportWidth * (pageHeight / pageWidth);

    final controller = DrawingController();
    // Annotation on Page 1 (will be deleted -> must NOT appear in exported pages)
    controller.addTextBox(DrawnTextBox(
      id: 'tb_p1',
      text: 'DeletedPage1Marker',
      position: const Offset(30, 40),
      color: Colors.black,
      fontSize: 14,
      pageNumber: 1,
    ));
    // Annotation on Page 2 (original Y inside page index 1 -> must land on exported page index 0)
    controller.addTextBox(DrawnTextBox(
      id: 'tb_p2',
      text: 'KeptPage2Marker',
      position: Offset(30, renderedH + pageSpacing + 50),
      color: Colors.blue,
      fontSize: 14,
      pageNumber: 2,
    ));
    // Annotation on Page 3 (original Y inside page index 2 -> must land on exported page index 1)
    controller.addTextBox(DrawnTextBox(
      id: 'tb_p3',
      text: 'KeptPage3Marker',
      position: Offset(30, (renderedH + pageSpacing) * 2 + 60),
      color: Colors.green,
      fontSize: 14,
      pageNumber: 3,
    ));

    final tempDir = await Directory.systemTemp.createTemp('pdfreor_export_test_');
    try {
      final outFile = File('${tempDir.path}/test_out.pdf');
      await outFile.writeAsBytes(baseBytes);

      await PdfExportService.exportToFile(
        file: outFile,
        baseBytes: baseBytes,
        drawingController: controller,
        viewportWidth: viewportWidth,
        textBoxFont: AppFontFamily.sansSerif,
        deletedZeroIndexedPages: const [0], // Delete Page 1
        addedPagesCount: 1, // Add 1 blank page at end -> total 3 pages (P2, P3, Blank)
      );

      // Verify no leftover .tmp files exist
      final leftovers = tempDir.listSync().where((e) => e.path.contains('.tmp.')).toList();
      expect(leftovers.isEmpty, true);

      final reloadedBytes = await outFile.readAsBytes();
      final verifyDoc = PdfDocument(inputBytes: reloadedBytes);
      expect(verifyDoc.pages.count, 3);

      final extractor = PdfTextExtractor(verifyDoc);
      final textPage0 = extractor.extractText(startPageIndex: 0, endPageIndex: 0);
      final textPage1 = extractor.extractText(startPageIndex: 1, endPageIndex: 1);
      final textPage2 = extractor.extractText(startPageIndex: 2, endPageIndex: 2);
      verifyDoc.dispose();

      expect(textPage0.contains('DeletedPage1Marker'), false);
      expect(textPage0.contains('KeptPage2Marker'), true);
      expect(textPage1.contains('KeptPage3Marker'), true);
      expect(textPage2.trim().isEmpty, true);
    } finally {
      controller.dispose();
      await tempDir.delete(recursive: true);
    }
  });

  test('PdfExportService maps pdfrx pageDocBounds with centered mixed-width pages accurately', () async {
    final srcDoc = PdfDocument();
    srcDoc.pageSettings.margins.all = 0;
    srcDoc.pageSettings.size = const Size(800, 600);
    srcDoc.pages.add();

    final sec2 = srcDoc.sections!.add();
    sec2.pageSettings.margins.all = 0;
    sec2.pageSettings.size = const Size(400, 600);
    sec2.pages.add();

    final baseBytes = Uint8List.fromList(srcDoc.saveSync());
    srcDoc.dispose();

    // Normalized layout width = 400 -> k = 800 / 400 = 2.0
    // Page 1 (800x600): Rect(0, 0, 400, 300)
    // Page 2 (400x600, centered in 800pt width -> left=200pt -> 100 normalized): Rect(100, 304, 200, 300)
    final pageDocBounds = <Rect>[
      const Rect.fromLTWH(0, 0, 400, 300),
      const Rect.fromLTWH(100, 304, 200, 300),
    ];

    final controller = DrawingController();
    controller.addTextBox(DrawnTextBox(
      id: 'tb_centered_p2',
      text: 'CenteredMarker',
      position: const Offset(120, 340),
      color: Colors.black,
      fontSize: 12,
      pageNumber: 2,
      width: 160,
    ));
    controller.startStroke(const Offset(130, 360), 0.7);
    controller.addStrokePoint(const Offset(220, 400), 0.8);
    controller.endStroke(Colors.red, 3.0, 2);

    controller.startShape(const Offset(120, 410));
    controller.updateShape(const Offset(250, 470));
    controller.endShape(ShapeType.rectangle, Colors.blue, 2.5, 2);

    controller.startShape(const Offset(120, 480));
    controller.updateShape(const Offset(250, 540));
    controller.endShape(ShapeType.roundedRectangle, Colors.green, 2.5, 2);

    controller.addTextAnnotation(DrawnTextAnnotation(
      type: TextAnnotationType.highlight,
      rects: const [Rect.fromLTWH(115, 320, 140, 16)],
      color: Colors.yellow,
      pageNumber: 2,
    ));

    try {
      final outBytes = await PdfExportService.buildExportBytes(
        baseBytes: baseBytes,
        drawingController: controller,
        viewportWidth: 400.0,
        textBoxFont: AppFontFamily.sansSerif,
        pageDocBounds: pageDocBounds,
      );

      final verifyDoc = PdfDocument(inputBytes: outBytes);
      expect(verifyDoc.pages.count, 2);
      final extractor = PdfTextExtractor(verifyDoc);
      final textLines = extractor.extractTextLines(startPageIndex: 1, endPageIndex: 1);
      final fullTextP2 = extractor.extractText(startPageIndex: 1, endPageIndex: 1);
      verifyDoc.dispose();

      expect(fullTextP2.contains('CenteredMarker'), true);
      expect(textLines.isNotEmpty, true);
      // Expected X on 400pt page: (120 - 100 + 4) * (400 / 200) = 48pt (not (120 + 4)*2 = 248pt!)
      expect(textLines.first.bounds.left, closeTo(48.0, 2.0));
    } finally {
      controller.dispose();
    }
  });
}

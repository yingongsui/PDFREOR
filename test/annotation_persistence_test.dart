import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/controllers/drawing_controller.dart';
import 'package:pdfreor/models/editor_models.dart';
import 'package:pdfreor/services/annotation_persistence_codec.dart';
import 'package:pdfreor/services/editor_settings_service.dart';
import 'package:pdfreor/services/export/pdf_editable_layer_helper.dart';
import 'package:pdfreor/services/export/pdf_export_models.dart';
import 'package:pdfreor/services/pdf_export_service.dart';
import 'package:pdfreor/widgets/pdf_floating_toolbar.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

Uint8List _createSamplePdfBytes({int pageCount = 2}) {
  final doc = sf.PdfDocument();
  for (int i = 0; i < pageCount; i++) {
    final page = doc.pages.add();
    page.graphics.drawString(
      'Sample Page ${i + 1}',
      sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 14),
      bounds: const Rect.fromLTWH(24, 24, 200, 30),
    );
  }
  final bytes = Uint8List.fromList(doc.saveAsBytesSync());
  doc.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AnnotationPersistenceCodec round-trips all annotation types and rescales across screen sizes', () {
    final sharedImgBytes = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3, 4]);
    final payload = ExportJobPayload(
      baseBytes: Uint8List(0),
      viewportWidth: 400,
      textBoxFont: AppFontFamily.sansSerif,
      deletedZeroIndexedPages: const [],
      addedPagesCount: 0,
      pageSpacing: 4,
      pageDocBounds: const [(0, 0, 400, 600), (0, 604, 400, 600)],
      textAnnotations: const [
        ExportTextAnnotationDto(
          id: 'ta1',
          type: TextAnnotationType.highlight,
          rects: [(40, 60, 120, 20)],
          colorArgb: 0xFFFFFF00,
          pageNumber: 1,
        ),
      ],
      strokes: const [
        ExportStrokeDto(
          id: 's1',
          points: [(20, 30, 0.8), (80, 90, 1.0)],
          colorArgb: 0xFF1E88E5,
          strokeWidth: 3.5,
        ),
      ],
      shapes: const [
        ExportShapeDto(
          id: 'sh1',
          type: ShapeType.roundedRectangle,
          startX: 50,
          startY: 650,
          endX: 150,
          endY: 750,
          colorArgb: 0xFFE53935,
          strokeWidth: 2.5,
        ),
      ],
      textBoxes: const [
        ExportTextBoxDto(
          id: 'tb1',
          index: 0,
          text: r'\frac{a}{b}',
          posX: 100,
          posY: 120,
          fontSize: 18,
          colorArgb: 0xFF212121,
          width: 160,
          isLatex: true,
          preRasterKey: null,
        ),
      ],
      images: const [
        ExportImageDto(
          id: 'im1',
          posX: 60,
          posY: 700,
          width: 80,
          height: 40,
          cacheKey: 'k_img_1',
        ),
        ExportImageDto(
          id: 'im2',
          posX: 200,
          posY: 700,
          width: 40,
          height: 40,
          cacheKey: 'k_img_1',
        ),
      ],
      preRasterizedLatex: const {},
      preRasterizedFallbacks: const {},
      optimizedImages: {'k_img_1': sharedImgBytes},
      embedEditableData: true,
    );

    final bundle = AnnotationPersistenceCodec.buildBundleFromExportPayload(
      payload: payload,
      origPageBounds: const [
        Rect.fromLTWH(0, 0, 400, 600),
        Rect.fromLTWH(0, 604, 400, 600),
      ],
      oldToNewPageIdx: const [0, 1],
      postEditPageSizes: const [(600, 900), (600, 900)],
    );

    // Identical image cache keys deduplicate into a single entry in imagePool.
    expect(bundle.imagePool.length, 1);

    final gz = AnnotationPersistenceCodec.encodeGzip(bundle);
    final decoded = AnnotationPersistenceCodec.decodeGzip(gz);
    expect(decoded, isNotNull);

    // Simulate reopening in landscape/larger viewport (2x width & height).
    final restored = decoded!.toModelLists(
      const [
        Rect.fromLTWH(0, 0, 800, 1200),
        Rect.fromLTWH(0, 1208, 800, 1200),
      ],
      const [Size(600, 900), Size(600, 900)],
    );

    expect(restored.strokes.length, 1);
    expect(restored.strokes.first.id, 's1');
    expect(restored.strokes.first.points.first.offset.dx, closeTo(40, 0.2));
    expect(restored.strokes.first.points.first.offset.dy, closeTo(60, 0.2));

    expect(restored.shapes.length, 1);
    expect(restored.shapes.first.id, 'sh1');
    expect(restored.shapes.first.type, ShapeType.roundedRectangle);
    expect(restored.shapes.first.start.dx, closeTo(100, 0.2));
    expect(restored.shapes.first.start.dy, closeTo(1300, 0.2));

    expect(restored.textBoxes.length, 1);
    expect(restored.textBoxes.first.isLatex, true);
    expect(restored.textBoxes.first.text, r'\frac{a}{b}');
    expect(restored.textBoxes.first.width, closeTo(320, 0.2));

    expect(restored.images.length, 2);
    expect(restored.images[0].imageBytes, sharedImgBytes);
    expect(restored.images[1].imageBytes, sharedImgBytes);

    expect(restored.textAnnotations.length, 1);
    expect(restored.textAnnotations.first.rects.first.left, closeTo(80, 0.2));

    // Corrupted gzip gracefully returns null instead of throwing.
    expect(
      AnnotationPersistenceCodec.decodeGzip(Uint8List.fromList([1, 2, 3, 4, 5])),
      isNull,
    );
  });

  test('Advanced export -> inspect -> modify/delete -> re-export -> export flattened round-trip', () async {
    final baseBytes = _createSamplePdfBytes(pageCount: 2);
    final pageBounds = const [
      Rect.fromLTWH(0, 0, 400, 600),
      Rect.fromLTWH(0, 604, 400, 600),
    ];
    final pdfPageSizes = const [Size(595, 842), Size(595, 842)];

    final controller1 = DrawingController();
    controller1.restorePersistedAnnotations(
      strokes: [
        DrawingStroke(
          id: 'stroke_1',
          points: const [
            StrokePoint(offset: Offset(40, 80)),
            StrokePoint(offset: Offset(180, 140)),
          ],
          color: const Color(0xFF1E88E5),
          strokeWidth: 4.0,
          pageNumber: 1,
        ),
      ],
      shapes: [
        DrawnShape(
          id: 'shape_1',
          type: ShapeType.roundedRectangle,
          start: const Offset(60, 640),
          end: const Offset(220, 760),
          color: const Color(0xFFE53935),
          strokeWidth: 3.0,
          pageNumber: 2,
        ),
      ],
      textBoxes: [
        DrawnTextBox(
          id: 'tb_1',
          text: 'Editable note',
          position: const Offset(80, 220),
          color: const Color(0xFF212121),
          pageNumber: 1,
        ),
      ],
      images: const [],
      textAnnotations: const [],
    );

    // Round 1: Export in Advanced Editable mode.
    final editableBytes1 = await PdfExportService.buildExportBytes(
      baseBytes: baseBytes,
      drawingController: controller1,
      viewportWidth: 400,
      textBoxFont: AppFontFamily.sansSerif,
      pageDocBounds: pageBounds,
      pdfPageSizes: pdfPageSizes,
      embedEditableData: true,
    );

    final inspect1 = await PdfExportService.inspectPdfDocument(
      editableBytes1,
      prepareCleanBaseForEditable: true,
    );
    expect(inspect1.hasEditablePayload, true);
    expect(inspect1.bundle, isNotNull);
    expect(inspect1.cleanBaseBytes, isNotNull);

    // Re-inspecting stripped cleanBaseBytes confirms marker + attachment were cleaned.
    final cleanCheck = await PdfExportService.inspectPdfDocument(
      inspect1.cleanBaseBytes!,
      prepareCleanBaseForEditable: false,
    );
    expect(cleanCheck.hasEditablePayload, false);

    // Restore into a second controller (simulating closing & reopening the file).
    final controller2 = DrawingController();
    final restored1 = inspect1.bundle!.toModelLists(pageBounds, pdfPageSizes);
    controller2.restorePersistedAnnotations(
      strokes: restored1.strokes,
      shapes: restored1.shapes,
      textBoxes: restored1.textBoxes,
      images: restored1.images,
      textAnnotations: restored1.textAnnotations,
    );
    expect(controller2.strokes.length, 1);
    expect(controller2.shapes.length, 1);
    expect(controller2.shapes.first.type, ShapeType.roundedRectangle);
    expect(controller2.textBoxes.length, 1);
    expect(controller2.hasUnsavedChanges, false);

    // Round 2: Delete stroke, move shape, add another text box, re-save onto cleanBaseBytes.
    controller2.deleteStroke(controller2.strokes.first.id);
    controller2.shapes.first.start = const Offset(100, 680);
    controller2.updateDrawnShape(controller2.shapes.first);
    controller2.addTextBox(
      DrawnTextBox(
        id: 'tb_2',
        text: 'Second note',
        position: const Offset(120, 320),
        color: const Color(0xFF212121),
        pageNumber: 1,
      ),
    );
    expect(controller2.hasUnsavedChanges, true);

    final editableBytes2 = await PdfExportService.buildExportBytes(
      baseBytes: inspect1.cleanBaseBytes!,
      drawingController: controller2,
      viewportWidth: 400,
      textBoxFont: AppFontFamily.sansSerif,
      pageDocBounds: pageBounds,
      pdfPageSizes: pdfPageSizes,
      embedEditableData: true,
    );

    final inspect2 = await PdfExportService.inspectPdfDocument(
      editableBytes2,
      prepareCleanBaseForEditable: true,
    );
    expect(inspect2.hasEditablePayload, true);
    final restored2 = inspect2.bundle!.toModelLists(pageBounds, pdfPageSizes);
    expect(restored2.strokes, isEmpty);
    expect(restored2.shapes.length, 1);
    expect(restored2.shapes.first.start.dx, closeTo(100, 0.5));
    expect(restored2.textBoxes.length, 2);

    // Verify Syncfusion attachment count did not duplicate.
    final checkDoc = sf.PdfDocument(inputBytes: editableBytes2);
    expect(checkDoc.attachments.count, 1);
    expect(checkDoc.attachments[0].fileName, kPdfreorAnnotationAttachmentName);
    checkDoc.dispose();

    // Round 3: Export Standard Flattened PDF from editable session.
    final flattenedBytes = await PdfExportService.buildExportBytes(
      baseBytes: inspect2.cleanBaseBytes!,
      drawingController: controller2,
      viewportWidth: 400,
      textBoxFont: AppFontFamily.sansSerif,
      pageDocBounds: pageBounds,
      pdfPageSizes: pdfPageSizes,
      embedEditableData: false,
    );

    final inspectFlat = await PdfExportService.inspectPdfDocument(
      flattenedBytes,
      prepareCleanBaseForEditable: true,
    );
    expect(inspectFlat.hasEditablePayload, false);

    final flatDoc = sf.PdfDocument(inputBytes: flattenedBytes);
    expect(flatDoc.pages.count, 2);
    expect(flatDoc.attachments.count, 0);
    expect(PdfEditableLayerHelper.stripAnnotationStreams(flatDoc), false);
    flatDoc.dispose();
  });

  test('inspectPdfDocument rejects mismatched external page count safely', () async {
    final base2Pages = _createSamplePdfBytes(pageCount: 2);
    final controller = DrawingController()
      ..restorePersistedAnnotations(
        strokes: const [],
        shapes: [
          DrawnShape(
            id: 'sh_mismatch',
            type: ShapeType.rectangle,
            start: const Offset(20, 20),
            end: const Offset(100, 100),
            color: const Color(0xFF000000),
            strokeWidth: 2.0,
            pageNumber: 1,
          ),
        ],
        textBoxes: const [],
        images: const [],
        textAnnotations: const [],
      );
    final editable2Pages = await PdfExportService.buildExportBytes(
      baseBytes: base2Pages,
      drawingController: controller,
      viewportWidth: 400,
      textBoxFont: AppFontFamily.sansSerif,
      pageDocBounds: const [
        Rect.fromLTWH(0, 0, 400, 600),
        Rect.fromLTWH(0, 604, 400, 600),
      ],
      pdfPageSizes: const [Size(595, 842), Size(595, 842)],
      embedEditableData: true,
    );

    // Simulate external PDF tool adding a 3rd page while preserving attachment.
    final doc = sf.PdfDocument(inputBytes: editable2Pages);
    doc.pages.add();
    final tamperedBytes = Uint8List.fromList(doc.saveAsBytesSync());
    doc.dispose();

    final inspect = await PdfExportService.inspectPdfDocument(
      tamperedBytes,
      prepareCleanBaseForEditable: true,
    );
    expect(inspect.hasEditablePayload, false);
  });

  testWidgets('PdfFloatingToolbar tap triggers onSave and long press triggers onSaveOptions', (tester) async {
    int saveCount = 0;
    int saveOptionsCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              PdfFloatingToolbar(
                activeTool: EditorTool.select,
                activeShape: ShapeType.rectangle,
                activeColor: Colors.black,
                activeStrokeWidth: 3.0,
                isStylusDetected: false,
                stylusOnlyMode: false,
                canUndo: false,
                onToolSelected: (_) {},
                onShapeSelected: (_) {},
                onColorSelected: (_) {},
                onStrokeWidthSelected: (_) {},
                onStylusOnlyModeToggled: (_) {},
                onUndo: () {},
                onManagePages: () {},
                onSave: () => saveCount++,
                onSaveOptions: () => saveOptionsCount++,
              ),
            ],
          ),
        ),
      ),
    );

    final saveIcon = find.byIcon(Icons.save_rounded);
    expect(saveIcon, findsOneWidget);
    await tester.ensureVisible(saveIcon);
    await tester.pumpAndSettle();

    await tester.longPress(saveIcon);
    await tester.pumpAndSettle();
    expect(saveOptionsCount, 1);
    expect(saveCount, 0);

    await tester.tap(saveIcon);
    await tester.pump(const Duration(seconds: 2));
    expect(saveCount, 1);
  });

  test('Repeated move + reopen + save cycles keep PDF size and resource counts constant', () async {
    var baseBytes = _createSamplePdfBytes(pageCount: 2);
    const pageBounds = [
      Rect.fromLTWH(0, 0, 400, 600),
      Rect.fromLTWH(0, 604, 400, 600),
    ];
    const pdfSizes = [Size(595, 842), Size(595, 842)];

    late Uint8List round1Bytes;
    var curBytes = baseBytes;

    for (int round = 1; round <= 4; round++) {
      final ctrl = DrawingController();
      if (round > 1) {
        final inspected = await PdfExportService.inspectPdfDocument(
          curBytes,
          prepareCleanBaseForEditable: true,
        );
        expect(inspected.hasEditablePayload, true);
        baseBytes = inspected.cleanBaseBytes!;
        final r = inspected.bundle!.toModelLists(pageBounds, pdfSizes);
        ctrl.restorePersistedAnnotations(
          strokes: r.strokes,
          shapes: r.shapes,
          textBoxes: r.textBoxes,
          images: r.images,
          textAnnotations: r.textAnnotations,
        );
        ctrl.shapes.first.start = Offset(40.0 + round * 12, 60.0 + round * 8);
        ctrl.shapes.first.end = Offset(140.0 + round * 12, 160.0 + round * 8);
        ctrl.updateDrawnShape(ctrl.shapes.first);
      } else {
        ctrl.restorePersistedAnnotations(
          strokes: [
            DrawingStroke(
              id: 's1',
              points: const [
                StrokePoint(offset: Offset(50, 50)),
                StrokePoint(offset: Offset(120, 120)),
              ],
              color: const Color(0xFF000000),
              strokeWidth: 3.0,
              pageNumber: 1,
            ),
          ],
          shapes: [
            DrawnShape(
              id: 'sh1',
              type: ShapeType.roundedRectangle,
              start: const Offset(40, 60),
              end: const Offset(140, 160),
              color: const Color(0xFFE53935),
              strokeWidth: 2.0,
              pageNumber: 1,
            ),
          ],
          textBoxes: [
            DrawnTextBox(
              id: 'tb1',
              text: 'Editable note',
              position: const Offset(80, 200),
              color: const Color(0xFF212121),
              pageNumber: 1,
            ),
          ],
          images: const [],
          textAnnotations: [
            DrawnTextAnnotation(
              id: 'ta1',
              type: TextAnnotationType.highlight,
              rects: const [Rect.fromLTWH(20, 20, 100, 15)],
              color: const Color(0xFFFFFF00),
              pageNumber: 1,
            ),
          ],
        );
      }

      curBytes = await PdfExportService.buildExportBytes(
        baseBytes: baseBytes,
        drawingController: ctrl,
        viewportWidth: 400,
        textBoxFont: AppFontFamily.sansSerif,
        pageDocBounds: pageBounds,
        pdfPageSizes: pdfSizes,
        embedEditableData: true,
      );

      if (round == 1) {
        round1Bytes = curBytes;
      } else {
        // Variance across rounds must stay negligible (gzip/deflate jitter only),
        // never leaking wrapper streams or resource entries per save.
        expect(
          (curBytes.length - round1Bytes.length).abs(),
          lessThan(64),
          reason: 'Round $round size ${curBytes.length} drifted from Round 1 ${round1Bytes.length}',
        );
      }
    }
  });
}

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/controllers/drawing_controller.dart';
import 'package:pdfreor/models/editor_models.dart';
import 'package:pdfreor/widgets/pdf_editor_canvas.dart';

void main() {
  group('DrawingController & Stroke Eraser Tests', () {
    test('Draw stroke, erase continuous stroke upon touch, and undo', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      // 1. Draw a stroke from (10, 10) to (50, 50)
      controller.startStroke(const Offset(10, 10), 1.0);
      controller.addStrokePoint(const Offset(30, 30), 1.0);
      controller.addStrokePoint(const Offset(50, 50), 1.0);
      controller.endStroke(Colors.black, 3.0, 1);

      expect(controller.strokes.length, 1);
      expect(controller.strokes.first.points.length, 3);
      expect(controller.canUndo, true);

      // 2. Erasing far away should NOT delete the stroke
      final erasedFar = controller.eraseAt(const Offset(200, 200), 1);
      expect(erasedFar, false);
      expect(controller.strokes.length, 1);

      // 3. Erasing on or near the stroke should delete the entire continuous stroke
      final erasedHit = controller.eraseAt(const Offset(31, 29), 1);
      expect(erasedHit, true);
      expect(controller.strokes.isEmpty, true);

      // 4. Undo should restore the erased continuous stroke
      controller.undo();
      expect(controller.strokes.length, 1);
      expect(controller.strokes.first.points.length, 3);
    });

    test('Draw shape, erase shape, and undo', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      // Draw rectangle from (20, 20) to (100, 100)
      controller.startShape(const Offset(20, 20));
      controller.updateShape(const Offset(100, 100));
      controller.endShape(ShapeType.rectangle, Colors.blue, 2.0, 1);

      expect(controller.shapes.length, 1);

      // Erase near rectangle top edge
      final erased = controller.eraseAt(const Offset(50, 20), 1);
      expect(erased, true);
      expect(controller.shapes.isEmpty, true);

      // Undo restores shape
      controller.undo();
      expect(controller.shapes.length, 1);
    });

    test('Single-point dot drawing and erasing', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      controller.startStroke(const Offset(45, 45), 1.0);
      controller.endStroke(Colors.red, 4.0, 1);

      expect(controller.strokes.length, 1);
      expect(controller.strokes.first.points.length, 1);

      final erased = controller.eraseAt(const Offset(45, 45), 1);
      expect(erased, true);
      expect(controller.strokes.isEmpty, true);
    });

    test('Unsaved changes tracking and markSaved', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);
      expect(controller.hasUnsavedChanges, false);

      // Add a stroke -> should have unsaved changes
      controller.startStroke(const Offset(10, 10), 1.0);
      controller.endStroke(Colors.black, 2.0, 1);
      expect(controller.hasUnsavedChanges, true);

      // Mark saved -> should be false while strokes still exist
      controller.markSaved();
      expect(controller.hasUnsavedChanges, false);
      expect(controller.strokes.isNotEmpty, true);
      controller.clearAll();
      expect(controller.hasUnsavedChanges, false);

      // Add text box
      controller.addTextBox(DrawnTextBox(
        id: '1',
        text: 'Hello',
        position: const Offset(10, 10),
        color: Colors.black,
        fontSize: 16.0,
        pageNumber: 1,
      ));
      expect(controller.hasUnsavedChanges, true);
      controller.clearAll();
      expect(controller.hasUnsavedChanges, false);

      // Add image
      controller.addImage(DrawnImage(
        id: 'img1',
        imageBytes: Uint8List.fromList([1, 2, 3]),
        position: const Offset(50, 50),
        width: 100,
        height: 100,
        pageNumber: 1,
      ));
      expect(controller.images.length, 1);
      expect(controller.hasUnsavedChanges, true);

      // Delete image
      controller.deleteImage('img1');
      expect(controller.images.isEmpty, true);

      // Undo restores image
      controller.undo();
      expect(controller.images.length, 1);
    });

    test('Shape editing, hit testing, resizing and undo', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      // 1. Draw a rectangle
      controller.startShape(const Offset(50, 50));
      controller.updateShape(const Offset(200, 150));
      controller.endShape(ShapeType.rectangle, Colors.blue, 2.0, 1);

      expect(controller.shapes.length, 1);
      final shape = controller.shapes.first;
      expect(shape.start, const Offset(50, 50));
      expect(shape.end, const Offset(200, 150));

      // 2. Hit testing
      // (50, 50) is the top-left corner -> should hit
      expect(controller.hitTestShape(const Offset(50, 50)), isNotNull);
      // (100, 50) is on top edge -> should hit
      expect(controller.hitTestShape(const Offset(100, 50)), isNotNull);
      // (500, 500) is far away -> should NOT hit
      expect(controller.hitTestShape(const Offset(500, 500)), isNull);

      // 3. Edit / resize the shape
      final oldStart = shape.start;
      final oldEnd = shape.end;
      shape.start = const Offset(30, 40);
      shape.end = const Offset(250, 180);
      controller.updateDrawnShape(shape);
      controller.recordShapeModification(shape, oldStart, oldEnd);

      expect(controller.shapes.first.start, const Offset(30, 40));
      expect(controller.shapes.first.end, const Offset(250, 180));

      // 4. Undo restores original size
      controller.undo();
      expect(controller.shapes.first.start, const Offset(50, 50));
      expect(controller.shapes.first.end, const Offset(200, 150));

      // 5. Delete shape and undo
      controller.deleteDrawnShape(shape.id);
      expect(controller.shapes.isEmpty, true);

      controller.undo();
      expect(controller.shapes.length, 1);
      expect(controller.shapes.first.id, shape.id);
    });

    test('TextBox deletion undo, Image move/resize undo, and split layer listenables', () {
      final controller = DrawingController();
      int savedNotifies = 0;
      int activeNotifies = 0;
      controller.savedLayerListenable.addListener(() => savedNotifies++);
      controller.activeLayerListenable.addListener(() => activeNotifies++);

      // High-frequency stroke points must ONLY notify activeLayerListenable
      controller.startStroke(const Offset(10, 10), 0.5);
      controller.addStrokePoint(const Offset(20, 20), 0.6);
      controller.addStrokePoint(const Offset(30, 30), 0.7);
      expect(activeNotifies, 3);
      expect(savedNotifies, 0);

      controller.endStroke(Colors.black, 3.0, 1);
      expect(savedNotifies, 1);

      // Add non-empty TextBox, delete it, and undo
      final tb = DrawnTextBox(
        id: 'tb_undo',
        text: 'Important Note',
        position: const Offset(40, 60),
        color: Colors.red,
        fontSize: 16.0,
        pageNumber: 1,
        width: 200.0,
      );
      controller.addTextBox(tb);
      expect(controller.textBoxes.length, 1);

      controller.deleteTextBox('tb_undo');
      expect(controller.textBoxes.isEmpty, true);

      controller.undo();
      expect(controller.textBoxes.length, 1);
      expect(controller.textBoxes.first.text, 'Important Note');

      // Image move/resize undo
      final img = DrawnImage(
        id: 'img_move',
        imageBytes: Uint8List.fromList([1, 2, 3, 4]),
        position: const Offset(20, 30),
        width: 100,
        height: 80,
        pageNumber: 1,
      );
      controller.addImage(img);
      img.position = const Offset(120, 150);
      img.width = 200;
      img.height = 160;
      controller.updateImage(img);
      controller.recordImageModification(img, const Offset(20, 30), 100, 80);

      controller.undo();
      expect(controller.images.first.position, const Offset(20, 30));
      expect(controller.images.first.width, 100);
      expect(controller.images.first.height, 80);

      // Oval / ellipse perimeter hit-testing accuracy
      controller.startShape(const Offset(0, 100));
      controller.updateShape(const Offset(400, 220));
      controller.endShape(ShapeType.circle, Colors.green, 2.0, 1);
      expect(controller.hitTestShape(const Offset(200, 100)), isNotNull); // top arc
      expect(controller.hitTestShape(const Offset(200, 220)), isNotNull); // bottom arc
      expect(controller.hitTestShape(const Offset(200, 0)), isNull); // outside minor axis
      expect(controller.hitTestShape(const Offset(200, 160)), isNull); // hollow center

      controller.dispose();
    });

    testWidgets(
      'TextBox and Shape on later pages (docY >> viewportHeight) can be tapped, edited, and dragged',
      (tester) async {
        final controller = DrawingController();
        // Scroll down to page 10: document y = 8000 is at viewport y = 0
        final transformController = TransformationController(
          Matrix4.translationValues(0.0, -8000.0, 0.0),
        );
        addTearDown(() {
          transformController.dispose();
          controller.dispose();
        });

        final tb = DrawnTextBox(
          id: 'tb_page10',
          text: 'Page 10 Annotation',
          position: const Offset(100, 8100),
          color: Colors.black,
          fontSize: 16.0,
          pageNumber: 10,
          width: 200.0,
        );
        controller.addTextBox(tb);

        controller.startShape(const Offset(100, 8300));
        controller.updateShape(const Offset(260, 8400));
        controller.endShape(ShapeType.rectangle, Colors.blue, 2.0, 10);
        final shape = controller.shapes.first;

        String? editingTbId;
        String? selectedShapeId;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) {
                        return PdfEditorCanvas(
                          controller: controller,
                          transformationController: transformController,
                          activeTool: EditorTool.select,
                          activeShape: ShapeType.rectangle,
                          activeColor: Colors.black,
                          activeStrokeWidth: 2.0,
                          currentPage: 10,
                          stylusOnlyMode: false,
                          editingTextBoxId: editingTbId,
                          onEditingTextBoxChanged: (id) => setState(() => editingTbId = id),
                          selectedShapeId: selectedShapeId,
                          onSelectedShapeChanged: (id) => setState(() => selectedShapeId = id),
                          onAddTextBoxRequested: (_) {},
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );

        // 1. Drag TextBox at doc (100, 8100) -> viewport (100, 100) by (+50, +30)
        // (PanGestureRecognizer consumes kTouchSlop = 18px before firing onPanUpdate)
        await tester.dragFrom(const Offset(140, 112), const Offset(50, 30));
        await tester.pump();
        expect(tb.position.dx, greaterThan(120.0));
        expect(tb.position.dy, greaterThan(8110.0));

        // 2. Tap TextBox at its new viewport position to enter editing mode
        await tester.tapAt(Offset(tb.position.dx + 30.0, tb.position.dy - 8000.0 + 12.0));
        await tester.pump();
        expect(editingTbId, 'tb_page10');

        // 3. Tap Shape edge at doc (180, 8300) -> viewport (180, 300) to select it
        await tester.tapAt(const Offset(180, 300));
        await tester.pump();
        expect(selectedShapeId, shape.id);

        // 4. Drag selected Shape from viewport (180, 350) by (+50, +40)
        await tester.dragFrom(const Offset(180, 350), const Offset(50, 40));
        await tester.pump();
        expect(shape.start.dx, greaterThan(120.0));
        expect(shape.start.dy, greaterThan(8315.0));
        expect(shape.end.dx, greaterThan(280.0));
        expect(shape.end.dy, greaterThan(8415.0));
      },
    );

    test('Move stroke updates points and bounds cleanly and supports undo', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      controller.startStroke(const Offset(20, 30), 0.8);
      controller.addStrokePoint(const Offset(60, 70), 0.9);
      controller.endStroke(Colors.blue, 4.0, 1);
      final stroke = controller.strokes.single;

      // Warm cached bounds and path batches before moving
      final origBounds = stroke.getBounds();
      expect(origBounds, const Rect.fromLTRB(20, 30, 60, 70));
      expect(stroke.getPathBatches().isNotEmpty, true);

      controller.markSaved();
      expect(controller.hasUnsavedChanges, false);

      const moveDelta = Offset(45, -15);
      controller.moveStroke(stroke, moveDelta);
      controller.recordStrokeMove(stroke, moveDelta);

      expect(controller.hasUnsavedChanges, true);
      expect(stroke.points[0].offset, const Offset(65, 15));
      expect(stroke.points[1].offset, const Offset(105, 55));
      expect(stroke.getBounds(), const Rect.fromLTRB(65, 15, 105, 55));

      controller.undo();
      expect(stroke.points[0].offset, const Offset(20, 30));
      expect(stroke.points[1].offset, const Offset(60, 70));
      expect(stroke.getBounds(), origBounds);
      expect(controller.hitTestStroke(const Offset(20, 30)), stroke);
    });

    testWidgets(
      'Selected handwritten stroke on later page can be dragged to move and undone',
      (tester) async {
        final controller = DrawingController();
        // Scroll to page 10 and zoom to 2.0x to verify scale-aware delta handling
        final transformController = TransformationController(
          Matrix4.translationValues(0.0, -16000.0, 0.0)..scaleByDouble(2.0, 2.0, 1.0, 1.0),
        );
        addTearDown(() {
          transformController.dispose();
          controller.dispose();
        });

        controller.startStroke(const Offset(100, 8100), 1.0);
        controller.addStrokePoint(const Offset(180, 8100), 1.0);
        controller.endStroke(Colors.red, 4.0, 10);
        final stroke = controller.strokes.single;

        String? selectedStrokeId;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) {
                        return PdfEditorCanvas(
                          controller: controller,
                          transformationController: transformController,
                          activeTool: EditorTool.select,
                          activeShape: ShapeType.rectangle,
                          activeColor: Colors.black,
                          activeStrokeWidth: 2.0,
                          currentPage: 10,
                          stylusOnlyMode: false,
                          selectedStrokeId: selectedStrokeId,
                          onSelectedStrokeChanged: (id) =>
                              setState(() => selectedStrokeId = id),
                          onAddTextBoxRequested: (_) {},
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );

        // With translation (0, -16000) and scale 2.0:
        // doc (140, 8100) maps to viewport (280, 200).
        await tester.tapAt(const Offset(280, 200));
        await tester.pump();
        expect(selectedStrokeId, stroke.id);

        // Drag from viewport (280, 200) by screen (+100, +60) -> doc (+50, +30)
        // minus pan slop at 2.0x scale.
        await tester.dragFrom(const Offset(280, 200), const Offset(100, 60));
        await tester.pump();

        expect(selectedStrokeId, stroke.id);
        expect(stroke.points[0].offset.dx, greaterThan(120.0));
        expect(stroke.points[0].offset.dy, greaterThan(8110.0));
        expect(stroke.points[1].offset.dx, greaterThan(200.0));
        expect(stroke.points[1].offset.dy, greaterThan(8110.0));
        expect(controller.canUndo, true);

        controller.undo();
        await tester.pump();
        expect(stroke.points[0].offset.dx, closeTo(100.0, 0.001));
        expect(stroke.points[0].offset.dy, closeTo(8100.0, 0.001));
      },
    );

    test('Rounded rectangle hit testing, erasing, and undo', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      // Large 200x200 rounded rectangle from (100, 100) to (300, 300), radius = 20
      controller.startShape(const Offset(100, 100));
      controller.updateShape(const Offset(300, 300));
      controller.endShape(ShapeType.roundedRectangle, Colors.teal, 3.0, 1);

      final shape = controller.shapes.single;
      // Top edge midpoint hits
      expect(DrawingController.isPointNearShape(const Offset(200, 100), shape, 12.0), true);
      // Point on rounded top-left corner arc (center=(120,120), r=20) hits
      expect(DrawingController.isPointNearShape(const Offset(106, 106), shape, 12.0), true);
      // Sharp corner outside rounded arc misses with tight threshold
      expect(DrawingController.isPointNearShape(const Offset(100, 100), shape, 4.0), false);
      // Deep interior misses for large shape
      expect(DrawingController.isPointNearShape(const Offset(200, 200), shape, 24.0), false);

      expect(controller.eraseAt(const Offset(200, 100), 1), true);
      expect(controller.shapes.isEmpty, true);

      controller.undo();
      expect(controller.shapes.length, 1);
      expect(controller.shapes.single.type, ShapeType.roundedRectangle);
    });
  });
}


import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/controllers/drawing_controller.dart';
import 'package:pdfreor/models/editor_models.dart';
import 'package:pdfreor/services/png_encoder.dart';
import 'package:pdfreor/widgets/pdf_canvas_items.dart';
import 'package:pdfreor/widgets/pdf_editor_canvas.dart';

Uint8List _createTestPngBytes() {
  final rgba = Uint8List.fromList([
    0x1E, 0x90, 0xFF, 0xFF, 0x1E, 0x90, 0xFF, 0xFF,
    0x1E, 0x90, 0xFF, 0xFF, 0x1E, 0x90, 0xFF, 0xFF,
  ]);
  final payload = PngEncoder.encodeCompactAlphaPngIsolateSafe(
    rawRgba: rgba,
    width: 2,
    height: 2,
    logicalWidth: 2,
    logicalHeight: 2,
    colorR: 0x1E,
    colorG: 0x90,
    colorB: 0xFF,
  );
  return payload!.bytes;
}

void main() {
  final testPngBytes = _createTestPngBytes();

  Widget buildCanvasHarness({
    required DrawingController controller,
    required ValueChanged<String?> onSelectedImageChanged,
    String? Function()? getSelectedImageId,
    EditorTool activeTool = EditorTool.select,
    TransformationController? transformationController,
  }) {
    String? selectedImageId = getSelectedImageId?.call();
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: StatefulBuilder(
            builder: (context, setState) {
              selectedImageId = getSelectedImageId?.call() ?? selectedImageId;
              return ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  return PdfEditorCanvas(
                    controller: controller,
                    transformationController: transformationController,
                    activeTool: activeTool,
                    activeShape: ShapeType.rectangle,
                    activeColor: Colors.black,
                    activeStrokeWidth: 2.0,
                    currentPage: 1,
                    stylusOnlyMode: false,
                    selectedImageId: selectedImageId,
                    onSelectedImageChanged: (id) {
                      setState(() {
                        selectedImageId = id;
                      });
                      onSelectedImageChanged(id);
                    },
                    onAddTextBoxRequested: (_) {},
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  group('ImageCanvasItem resize & delete regression tests', () {
    testWidgets(
      'Dragging outer quadrant of bottom-right handle resizes pasted image and supports undo',
      (tester) async {
        final controller = DrawingController();
        addTearDown(controller.dispose);

        final img = DrawnImage(
          id: 'img_resize',
          imageBytes: testPngBytes,
          position: const Offset(100, 100),
          width: 200,
          height: 100,
          pageNumber: 1,
        );
        controller.addImage(img);

        String? selectedImageId;
        await tester.pumpWidget(
          buildCanvasHarness(
            controller: controller,
            onSelectedImageChanged: (id) => selectedImageId = id,
          ),
        );
        await tester.pump();

        await tester.tapAt(const Offset(200, 150));
        await tester.pump();
        expect(selectedImageId, 'img_resize');

        await tester.dragFrom(const Offset(306, 206), const Offset(80, 0));
        await tester.pump();

        expect(selectedImageId, 'img_resize');
        expect(img.width, greaterThan(240.0));
        expect(img.height, closeTo(img.width / 2.0, 0.5));

        final widthAfterHorizontalDrag = img.width;

        await tester.dragFrom(
          Offset(img.position.dx + img.width + 4, img.position.dy + img.height + 4),
          const Offset(0, 50),
        );
        await tester.pump();

        expect(img.width, greaterThan(widthAfterHorizontalDrag));
        expect(img.height, closeTo(img.width / 2.0, 0.5));

        controller.undo();
        await tester.pump();
        expect(img.width, closeTo(widthAfterHorizontalDrag, 0.5));
        expect(img.height, closeTo(widthAfterHorizontalDrag / 2.0, 0.5));
      },
    );

    testWidgets(
      'Pre-selected pasted image can be resized and deleted even when activeTool is pen',
      (tester) async {
        final controller = DrawingController();
        addTearDown(controller.dispose);

        final img = DrawnImage(
          id: 'img_pen_mode',
          imageBytes: testPngBytes,
          position: const Offset(80, 80),
          width: 160,
          height: 160,
          pageNumber: 1,
        );
        controller.addImage(img);

        String? selectedImageId = 'img_pen_mode';
        await tester.pumpWidget(
          buildCanvasHarness(
            controller: controller,
            activeTool: EditorTool.pen,
            getSelectedImageId: () => selectedImageId,
            onSelectedImageChanged: (id) => selectedImageId = id,
          ),
        );
        await tester.pump();

        await tester.dragFrom(const Offset(244, 244), const Offset(60, 60));
        await tester.pump();

        expect(controller.strokes, isEmpty);
        expect(img.width, greaterThan(190.0));
        expect(img.height, closeTo(img.width, 0.5));

        // Tap outer top-right delete button (top: -14, right: -14, size: 32x32)
        await tester.tapAt(
          Offset(img.position.dx + img.width + 8, img.position.dy - 8),
        );
        await tester.pump();

        expect(controller.images, isEmpty);
        expect(selectedImageId, isNull);
        expect(controller.strokes, isEmpty);
      },
    );

    testWidgets(
      'Tapping outer delete button removes image instead of deselecting',
      (tester) async {
        final controller = DrawingController();
        addTearDown(controller.dispose);

        final img = DrawnImage(
          id: 'img_delete',
          imageBytes: testPngBytes,
          position: const Offset(100, 100),
          width: 120,
          height: 80,
          pageNumber: 1,
        );
        controller.addImage(img);

        String? selectedImageId = 'img_delete';
        await tester.pumpWidget(
          buildCanvasHarness(
            controller: controller,
            getSelectedImageId: () => selectedImageId,
            onSelectedImageChanged: (id) => selectedImageId = id,
          ),
        );
        await tester.pump();

        await tester.tapAt(const Offset(228, 92));
        await tester.pump();

        expect(controller.images, isEmpty);
        expect(selectedImageId, isNull);
      },
    );

    testWidgets(
      'Standalone ImageCanvasItem resizes and deletes cleanly via outer handle and button',
      (tester) async {
        final img = DrawnImage(
          id: 'img_standalone',
          imageBytes: testPngBytes,
          position: const Offset(50, 50),
          width: 150,
          height: 100,
          pageNumber: 1,
        );
        bool deleted = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                height: 500,
                child: DocumentStack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: img.position.dx,
                      top: img.position.dy,
                      child: ImageCanvasItem(
                        image: img,
                        onUpdate: (newPos, newW, newH) {
                          img.position = newPos;
                          img.width = newW;
                          img.height = newH;
                        },
                        onModificationCommitted: (_, _, _) {},
                        onDelete: () => deleted = true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tapAt(const Offset(125, 100));
        await tester.pump();

        await tester.dragFrom(const Offset(205, 155), const Offset(60, 0));
        await tester.pump();

        expect(img.width, greaterThan(185.0));
        expect(img.height, closeTo(img.width * 100.0 / 150.0, 0.5));

        await tester.tapAt(
          Offset(img.position.dx + img.width + 8, img.position.dy - 8),
        );
        await tester.pump();
        expect(deleted, isTrue);
      },
    );
  });
}

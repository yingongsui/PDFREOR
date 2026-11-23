import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/controllers/drawing_controller.dart';
import 'package:pdfreor/models/editor_models.dart';
import 'package:pdfreor/widgets/pdf_editor_canvas.dart';

void main() {
  test('isEraserButtonPressed ignores mouse right-click and detects stylus eraser buttons', () {
    const mouseRightDown = PointerDownEvent(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
      position: Offset(20, 20),
    );
    expect(isEraserButtonPressed(mouseRightDown), isFalse);

    const stylusPrimaryDown = PointerDownEvent(
      kind: PointerDeviceKind.stylus,
      buttons: kPrimaryStylusButton,
      position: Offset(20, 20),
    );
    expect(isEraserButtonPressed(stylusPrimaryDown), isTrue);

    const stylusSecondaryDown = PointerDownEvent(
      kind: PointerDeviceKind.stylus,
      buttons: kSecondaryStylusButton,
      position: Offset(20, 20),
    );
    expect(isEraserButtonPressed(stylusSecondaryDown), isTrue);

    const stylusMappedRightDown = PointerDownEvent(
      kind: PointerDeviceKind.stylus,
      buttons: kSecondaryMouseButton,
      position: Offset(20, 20),
    );
    expect(isEraserButtonPressed(stylusMappedRightDown), isTrue);

    const invertedStylusDown = PointerDownEvent(
      kind: PointerDeviceKind.invertedStylus,
      buttons: kPrimaryStylusButton,
      position: Offset(20, 20),
    );
    expect(isEraserButtonPressed(invertedStylusDown), isTrue);
  });

  testWidgets(
    'Mouse right-click on PdfEditorCanvas does not flash eraser state, erase strokes, or draw',
    (tester) async {
      final controller = DrawingController();
      controller.startStroke(const Offset(100, 100), 0.5);
      controller.addStrokePoint(const Offset(140, 100), 0.5);
      controller.endStroke(Colors.black, 3.0, 1);
      expect(controller.strokes.length, 1);

      final eraserStates = <bool>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: PdfEditorCanvas(
                controller: controller,
                activeTool: EditorTool.pen,
                activeShape: ShapeType.rectangle,
                activeColor: Colors.black,
                activeStrokeWidth: 3.0,
                currentPage: 1,
                stylusOnlyMode: false,
                onPointerEraserStateChanged: eraserStates.add,
                onAddTextBoxRequested: (_) {},
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.down(const Offset(120, 100));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(eraserStates, isNot(contains(true)));
      expect(controller.strokes.length, 1);

      final stylusGesture = await tester.createGesture(
        kind: PointerDeviceKind.stylus,
        buttons: kSecondaryStylusButton,
      );
      await stylusGesture.down(const Offset(200, 200));
      await tester.pump();
      await stylusGesture.up();
      await tester.pump();

      expect(eraserStates, contains(true));
    },
  );
}

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/controllers/drawing_controller.dart';
import 'package:pdfreor/models/editor_models.dart';
import 'package:pdfreor/services/atomic_file_store.dart';
import 'package:pdfreor/services/png_encoder.dart';

void main() {
  group('v2.4.0 optimization regression tests', () {
    test('DrawingController preserves stroke Z-order on erase undo', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      for (int i = 0; i < 3; i++) {
        controller.startStroke(Offset(i * 40.0, 10), 1.0);
        controller.addStrokePoint(Offset(i * 40.0 + 20, 10), 1.0);
        controller.endStroke(Colors.black, 2.0 + i, 1);
      }

      expect(controller.strokes.map((s) => s.strokeWidth).toList(), [2.0, 3.0, 4.0]);

      final erasedMiddle = controller.eraseAt(const Offset(50, 10), 1);
      expect(erasedMiddle, isTrue);
      expect(controller.strokes.map((s) => s.strokeWidth).toList(), [2.0, 4.0]);

      controller.undo();
      expect(controller.strokes.map((s) => s.strokeWidth).toList(), [2.0, 3.0, 4.0]);
    });

    test('DrawingController caps undo history and supports cancelActiveShape', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      for (int i = 0; i < 140; i++) {
        controller.startStroke(Offset(0, i.toDouble()), 1.0);
        controller.addStrokePoint(Offset(10, i.toDouble()), 1.0);
        controller.endStroke(Colors.black, 2.0, 1);
      }
      expect(controller.strokes.length, 140);

      int undoSteps = 0;
      while (controller.canUndo) {
        controller.undo();
        undoSteps++;
      }
      expect(undoSteps, 120);
      expect(controller.strokes.length, 20);

      controller.startShape(const Offset(10, 10));
      controller.updateShape(const Offset(80, 80));
      expect(controller.activeShapeStart, isNotNull);
      controller.cancelActiveShape();
      expect(controller.activeShapeStart, isNull);
      expect(controller.activeShapeEnd, isNull);
    });

    test('isPointNearShape handles small rectangles cleanly', () {
      final rect = DrawnShape(
        id: nextAnnotationId(),
        type: ShapeType.rectangle,
        start: const Offset(100, 100),
        end: const Offset(108, 108),
        color: Colors.red,
        strokeWidth: 2.0,
        pageNumber: 1,
      );
      expect(DrawingController.isPointNearShape(const Offset(104, 104), rect), isTrue);
      expect(DrawingController.isPointNearShape(const Offset(140, 140), rect), isFalse);
      expect(nextAnnotationId(), isNot(equals(nextAnnotationId())));
    });

    test('PngEncoder crops transparent margin and emits valid PNG bytes', () {
      const w = 8;
      const h = 8;
      final rgba = Uint8List(w * h * 4);
      // Paint a 2x2 opaque blue block at (3, 3)..(4, 4) -> 1px border expands to 4x4
      for (int y = 3; y <= 4; y++) {
        for (int x = 3; x <= 4; x++) {
          final idx = (y * w + x) * 4;
          rgba[idx] = 0x1E;
          rgba[idx + 1] = 0x90;
          rgba[idx + 2] = 0xFF;
          rgba[idx + 3] = 0xFF;
        }
      }

      final payload = PngEncoder.encodeCompactAlphaPngIsolateSafe(
        rawRgba: rgba,
        width: w,
        height: h,
        logicalWidth: w.toDouble(),
        logicalHeight: h.toDouble(),
        colorR: 0x1E,
        colorG: 0x90,
        colorB: 0xFF,
      );
      expect(payload, isNotNull);
      expect(payload!.logicalWidth, 4.0);
      expect(payload.logicalHeight, 4.0);
      expect(payload.offsetX, 2.0);
      expect(payload.offsetY, 2.0);
      expect(payload.bytes.sublist(0, 8), PngEncoder.pngSignature);
    });

    test('AtomicFileStore serializes concurrent writes cleanly', () async {
      final tempDir = await Directory.systemTemp.createTemp('atomic_store_test_');
      try {
        final target = File('${tempDir.path}/state.json');
        await Future.wait([
          AtomicFileStore.writeString(target, 'first'),
          AtomicFileStore.writeString(target, 'second'),
          AtomicFileStore.writeString(target, 'third'),
        ]);
        expect(await target.exists(), isTrue);
        expect(await target.readAsString(), 'third');
        final leftover = tempDir
            .listSync()
            .where((e) => e.path.endsWith('.tmp'))
            .toList();
        expect(leftover, isEmpty);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}

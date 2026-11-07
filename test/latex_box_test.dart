import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/controllers/drawing_controller.dart';
import 'package:pdfreor/models/editor_models.dart';

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
  });
}

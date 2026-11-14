import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/models/editor_models.dart';
import 'package:pdfreor/services/editor_settings_service.dart';

void main() {
  test('EditorSettings serialization and defaults', () {
    const defaultSettings = EditorSettings();
    expect(defaultSettings.activeColor, const Color(0xFF212121));
    expect(defaultSettings.activeStrokeWidth, 3.0);
    expect(defaultSettings.activeShape, ShapeType.rectangle);
    expect(defaultSettings.latexQuickOperators.isNotEmpty, true);
    expect(
      defaultSettings.annotationPersistenceMode,
      AnnotationPersistenceMode.fileDefault,
    );

    final modified = defaultSettings.copyWith(
      activeColor: const Color(0xFF2196F3),
      activeStrokeWidth: 5.5,
      activeShape: ShapeType.roundedRectangle,
      latexQuickOperators: [r'\sum', r'\int', r'\alpha'],
      annotationPersistenceMode: AnnotationPersistenceMode.alwaysEditable,
    );

    final json = modified.toJson();
    final restored = EditorSettings.fromJson(json);

    expect(restored.activeColor.toARGB32(), const Color(0xFF2196F3).toARGB32());
    expect(restored.activeStrokeWidth, 5.5);
    expect(restored.activeShape, ShapeType.roundedRectangle);
    expect(restored.latexQuickOperators, [r'\sum', r'\int', r'\alpha']);
    expect(
      restored.annotationPersistenceMode,
      AnnotationPersistenceMode.alwaysEditable,
    );
  });

  test('EditorSettings.fromJson guards negative and out-of-range enum indices', () {
    final restored = EditorSettings.fromJson({
      'activeShape': -3,
      'textBoxFont': 999,
      'annotationPersistenceMode': 999,
    });
    expect(restored.activeShape, ShapeType.rectangle);
    expect(restored.textBoxFont, AppFontFamily.sansSerif);
    expect(
      restored.annotationPersistenceMode,
      AnnotationPersistenceMode.fileDefault,
    );

    final restoredNegativeFont = EditorSettings.fromJson({
      'activeShape': 999,
      'textBoxFont': -1,
      'annotationPersistenceMode': -2,
    });
    expect(restoredNegativeFont.activeShape, ShapeType.rectangle);
    expect(restoredNegativeFont.textBoxFont, AppFontFamily.sansSerif);
    expect(
      restoredNegativeFont.annotationPersistenceMode,
      AnnotationPersistenceMode.fileDefault,
    );
  });
}


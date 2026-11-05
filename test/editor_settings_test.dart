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

    final modified = defaultSettings.copyWith(
      activeColor: const Color(0xFF2196F3),
      activeStrokeWidth: 5.5,
      activeShape: ShapeType.arrow,
    );

    final json = modified.toJson();
    final restored = EditorSettings.fromJson(json);

    expect(restored.activeColor.toARGB32(), const Color(0xFF2196F3).toARGB32());
    expect(restored.activeStrokeWidth, 5.5);
    expect(restored.activeShape, ShapeType.arrow);
  });
}


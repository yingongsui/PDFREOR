import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/screens/settings/latex_operators_section.dart';
import 'package:pdfreor/services/editor_settings_service.dart';

void main() {
  testWidgets(
    'LatexOperatorsCard aligns \\neq composite glyphs without InputChip dry-layout shift',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LatexOperatorsCard(
                editorSettings: const EditorSettings(
                  latexQuickOperators: [r'\neq'],
                ),
                onSettingsUpdated: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final mathRo = tester.renderObject(find.byType(Math));
      RenderObject? flexRo;
      mathRo.visitChildren((child) => flexRo = child);
      expect(flexRo, isA<RenderFlex>());

      final offsets = <Offset>[];
      flexRo!.visitChildren((child) {
        offsets.add((child.parentData as BoxParentData).offset);
      });

      expect(offsets.length, 2);
      // The '=' glyph must be shifted down to match the baseline of '\not' ('/'),
      // rather than collapsing to Offset.zero due to cached dry-layout baselines.
      expect(offsets[1].dy, greaterThan(1.0));
    },
  );

  testWidgets('LatexOperatorsCard delete button removes operator', (tester) async {
    EditorSettings? updatedSettings;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LatexOperatorsCard(
              editorSettings: const EditorSettings(
                latexQuickOperators: [r'\neq', r'\leq'],
              ),
              onSettingsUpdated: (updated) async {
                updatedSettings = updated;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();

    expect(updatedSettings, isNotNull);
    expect(updatedSettings!.latexQuickOperators, [r'\leq']);
  });
}


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/screens/settings_screen.dart';
import 'package:pdfreor/services/editor_settings_service.dart';

void main() {
  testWidgets('SettingsScreen omits legacy mobile Local File Access permission section', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Editor & Annotation'), findsOneWidget);
    expect(find.text('Permissions'), findsNothing);
    expect(find.text('Local File Access'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Version 1.3.0'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Version 1.3.0'), findsOneWidget);
  });

  testWidgets('SettingsScreen updates Live Font Preview fontFamily on selection', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(),
      ),
    );
    await tester.pump();

    Text previewText() => tester.widget<Text>(
          find.text('One more time, 1 more chance.'),
        );

    expect(previewText().style?.fontFamily, AppFontFamily.sansSerif.fontFamily);

    await tester.tap(find.text('Serif'));
    await tester.pump();
    expect(previewText().style?.fontFamily, AppFontFamily.serif.fontFamily);
    expect(
      previewText().style?.fontFamilyFallback,
      AppFontFamily.serif.fontFamilyFallback,
    );

    await tester.tap(find.text('Mono'));
    await tester.pump();
    expect(previewText().style?.fontFamily, AppFontFamily.monospace.fontFamily);
    expect(
      previewText().style?.fontFamilyFallback,
      AppFontFamily.monospace.fontFamilyFallback,
    );
  });
}

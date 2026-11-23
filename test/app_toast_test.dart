import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/widgets/app_toast.dart';

void main() {
  testWidgets('AppToast shows floating pill, replaces active toast, and triggers action', (
    WidgetTester tester,
  ) async {
    bool undoCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                ElevatedButton(
                  onPressed: () => AppToast.show(
                    context,
                    'Saved as Standard (Flattened)!',
                    icon: Icons.check_circle_rounded,
                    backgroundColor: Colors.green,
                  ),
                  child: const Text('Save'),
                ),
                ElevatedButton(
                  onPressed: () => AppToast.show(
                    context,
                    'Hidden "Books"',
                    actionLabel: 'Undo',
                    onAction: () => undoCalled = true,
                  ),
                  child: const Text('Hide'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Saved as Standard (Flattened)!'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    await tester.tap(find.text('Hide'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Saved as Standard (Flattened)!'), findsNothing);
    expect(find.text('Hidden "Books"'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(undoCalled, isTrue);
    expect(find.text('Hidden "Books"'), findsNothing);
  });

  testWidgets('AppToast renders above modal dialogs via rootOverlay and auto-dismisses', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogCtx) => AlertDialog(
                  content: ElevatedButton(
                    onPressed: () => AppToast.show(
                      dialogCtx,
                      'Blank page added at the end',
                      duration: const Duration(milliseconds: 800),
                    ),
                    child: const Text('Add Page'),
                  ),
                ),
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Page'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Blank page added at the end'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Blank page added at the end'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/models/pdf_file_info.dart';
import 'package:pdfreor/screens/pdf_viewer_screen.dart';
import 'package:pdfreor/screens/viewer/pdf_search_bar.dart';
import 'package:pdfreor/services/pdf_tab_manager.dart';

void main() {
  testWidgets('PdfSearchBar forwards search, match-case, clear, and close callbacks', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    final changedValues = <String>[];
    final submittedValues = <String>[];
    var matchCaseToggled = 0;
    var closedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfSearchBar(
            controller: controller,
            focusNode: focusNode,
            searcher: null,
            matchCase: false,
            onChanged: changedValues.add,
            onSubmitted: submittedValues.add,
            onPrevious: () {},
            onNext: () {},
            onToggleMatchCase: () => matchCaseToggled++,
            onClose: () => closedCount++,
          ),
        ),
      ),
    );

    expect(find.text('Find in PDF...'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'flutter');
    await tester.pump();
    expect(changedValues, ['flutter']);
    expect(find.byTooltip('Clear query'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(submittedValues, ['flutter']);

    await tester.tap(find.text('Aa'));
    await tester.pump();
    expect(matchCaseToggled, 1);

    await tester.tap(find.byTooltip('Clear query'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(changedValues.last, '');

    await tester.tap(find.byTooltip('Close find'));
    await tester.pump();
    expect(closedCount, 1);
  });

  testWidgets('PdfViewerScreen places Find button left of Open Documents and toggles search', (
    tester,
  ) async {
    final file = PdfFileInfo(
      path: '/nonexistent_pdfreor_test/sample.pdf',
      name: 'sample.pdf',
      sizeInBytes: 128,
      lastModified: DateTime(2026, 1, 1),
    );
    addTearDown(() => PdfTabManager.instance.closeTabByPath(file.path));

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewerScreen(file: file),
      ),
    );
    await tester.pump();

    final findButton = find.byTooltip('Find in document');
    final openDocsButton = find.byTooltip('Open Documents');
    expect(findButton, findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.text('Find'), findsNothing);
    expect(openDocsButton, findsOneWidget);
    expect(
      tester.getCenter(findButton).dx,
      lessThan(tester.getCenter(openDocsButton).dx),
    );

    final tabState = tester.state<PdfTabContentState>(find.byType(PdfTabContent));
    expect(tabState.isSearchVisible, isFalse);

    await tester.tap(findButton);
    await tester.pump();
    expect(tabState.isSearchVisible, isTrue);

    await tester.tap(findButton);
    await tester.pump();
    expect(tabState.isSearchVisible, isFalse);
  });
}

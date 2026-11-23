import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/models/pdf_file_info.dart';
import 'package:pdfreor/screens/pdf_viewer_screen.dart';
import 'package:pdfreor/services/pdf_tab_manager.dart';
import 'package:pdfreor/widgets/pdf_find_bar.dart';

void main() {
  testWidgets('PdfFindBar shows status, toggles match case, and triggers actions', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController(text: 'matrix');
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    String? latestQuery;
    var toggledCase = 0;
    var nextCalls = 0;
    var prevCalls = 0;
    var closeCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 12,
                right: 16,
                child: PdfFindBar(
                  controller: controller,
                  focusNode: focusNode,
                  matchCase: false,
                  isSearching: false,
                  matchCount: 5,
                  currentMatchIndex: 1,
                  query: 'matrix',
                  onQueryChanged: (q) => latestQuery = q,
                  onToggleMatchCase: () => toggledCase++,
                  onFindNext: () => nextCalls++,
                  onFindPrevious: () => prevCalls++,
                  onClose: () => closeCalls++,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('2 / 5'), findsOneWidget);
    expect(find.text('Aa'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'theorem');
    expect(latestQuery, 'theorem');

    await tester.tap(find.text('Aa'));
    expect(toggledCase, 1);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    expect(nextCalls, 1);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    expect(prevCalls, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closeCalls, 1);

    await tester.tap(find.byIcon(Icons.close));
    expect(closeCalls, 2);
  });

  testWidgets('PdfViewerScreen places Find button left of opened-files button and toggles find bar state', (
    WidgetTester tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('pdf_viewer_find_test_');
    final pdfPath = '${tempDir.path}/missing_sample.pdf';

    addTearDown(() {
      PdfTabManager.instance.closeTabByPath(pdfPath);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final sampleFile = PdfFileInfo(
      name: 'sample.pdf',
      path: pdfPath,
      lastModified: DateTime(2026, 1, 1),
      sizeInBytes: 1024,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewerScreen(file: sampleFile),
      ),
    );
    await tester.pump();

    final findButton = find.byIcon(Icons.search);
    final openTabsIcon = find.byIcon(Icons.tab_rounded);
    expect(findButton, findsOneWidget);
    expect(find.text('Find'), findsNothing);
    expect(openTabsIcon, findsOneWidget);

    final findRect = tester.getRect(findButton);
    final openTabsRect = tester.getRect(openTabsIcon);
    expect(findRect.right, lessThan(openTabsRect.left));

    final tabState = tester.state<PdfTabContentState>(find.byType(PdfTabContent));
    expect(tabState.isFindBarVisible, isFalse);

    await tester.tap(findButton);
    await tester.pump();
    expect(tabState.isFindBarVisible, isTrue);

    await tester.tap(findButton);
    await tester.pump();
    expect(tabState.isFindBarVisible, isFalse);
  }, timeout: const Timeout(Duration(seconds: 15)));
}

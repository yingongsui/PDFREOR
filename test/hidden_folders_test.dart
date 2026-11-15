import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfreor/screens/home/home_dialogs.dart';
import 'package:pdfreor/screens/settings/hidden_folders_section.dart';
import 'package:pdfreor/services/pdf_scanner_service.dart';

void main() {
  test('PdfScannerService matches hidden folders without sibling prefix leaks', () {
    final hidden = ['/storage/emulated/0/Junk/'];
    expect(
      PdfScannerService.isPathInHiddenFolders('/storage/emulated/0/Junk', hidden),
      isTrue,
    );
    expect(
      PdfScannerService.isPathInHiddenFolders('/storage/emulated/0/Junk/sub/a.pdf', hidden),
      isTrue,
    );
    expect(
      PdfScannerService.isPathInHiddenFolders('/storage/emulated/0/Junk2/a.pdf', hidden),
      isFalse,
    );
    expect(
      PdfScannerService.isPathInHiddenFolders('/storage/emulated/0/Docs/a.pdf', hidden),
      isFalse,
    );
  });

  test('PdfScannerService background scan skips hidden folders and their subfolders', () async {
    final tempRoot = await Directory.systemTemp.createTemp('pdfreor_hidden_scan_');
    try {
      final visibleDir = Directory(p.join(tempRoot.path, 'visible'))..createSync();
      final spamDir = Directory(p.join(tempRoot.path, 'spam'))..createSync();
      final spamNestedDir = Directory(p.join(spamDir.path, 'nested'))..createSync();
      final siblingDir = Directory(p.join(tempRoot.path, 'spam_extra'))..createSync();

      final okPdf = File(p.join(visibleDir.path, 'ok.pdf'))..writeAsBytesSync(const [1, 2, 3]);
      final junkPdf = File(p.join(spamDir.path, 'junk.pdf'))..writeAsBytesSync(const [1, 2, 3]);
      File(p.join(spamNestedDir.path, 'nested_junk.pdf')).writeAsBytesSync(const [1, 2, 3]);
      final siblingPdf = File(p.join(siblingDir.path, 'keep.pdf'))
        ..writeAsBytesSync(const [1, 2, 3]);

      final found = PdfScannerService.scanPathsInBackgroundForTest(
        [tempRoot.path],
        [junkPdf.path],
        [spamDir.path],
      );

      final foundPaths = found.map((f) => f.path).toSet();
      expect(foundPaths, equals({okPdf.path, siblingPdf.path}));
    } finally {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    }
  });

  testWidgets('HiddenFoldersCard triggers add, unhide, and clear callbacks', (tester) async {
    var added = 0;
    var cleared = 0;
    String? removedPath;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HiddenFoldersCard(
            hiddenFolders: const ['/storage/emulated/0/Spam'],
            onAddFolder: () => added++,
            onRemoveFolder: (path) => removedPath = path,
            onClearAll: () => cleared++,
          ),
        ),
      ),
    );

    expect(find.text('Spam'), findsOneWidget);
    expect(find.text('/storage/emulated/0/Spam'), findsOneWidget);

    await tester.tap(find.byTooltip('Unhide folder'));
    await tester.pump();
    expect(removedPath, '/storage/emulated/0/Spam');

    await tester.tap(find.text('Clear All'));
    await tester.pump();
    expect(cleared, 1);

    await tester.tap(find.text('Add Folder'));
    await tester.pump();
    expect(added, 1);
  });

  testWidgets('showPdfFolderContextMenu triggers Hide Folder callback', (tester) async {
    var hidFolder = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showPdfFolderContextMenu(
                context,
                folderName: 'Cache',
                folderPath: '/storage/emulated/0/Cache',
                fileCount: 3,
                isCollapsed: false,
                canHide: true,
                onToggleCollapse: () {},
                onHideFolder: () => hidFolder = true,
              ),
              child: const Text('Open Menu'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Menu'));
    await tester.pumpAndSettle();

    expect(find.text('Cache'), findsOneWidget);
    expect(find.text('Hide Folder'), findsOneWidget);

    await tester.tap(find.text('Hide Folder'));
    await tester.pumpAndSettle();
    expect(hidFolder, isTrue);
  });
}

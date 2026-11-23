import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/screens/home/home_dialogs.dart';

void main() {
  testWidgets('showFolderContextMenu invokes onHideFolder when Hide Folder is tapped', (
    tester,
  ) async {
    bool hid = false;
    bool toggled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                showFolderContextMenu(
                  context,
                  folderName: 'TempDownloads',
                  folderPath: '/tmp/TempDownloads',
                  fileCount: 3,
                  isCollapsed: false,
                  onToggleCollapse: () => toggled = true,
                  onHideFolder: () => hid = true,
                );
              },
              child: const Text('Open Menu'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Menu'));
    await tester.pumpAndSettle();

    expect(find.text('TempDownloads'), findsOneWidget);
    expect(find.text('3 files • /tmp/TempDownloads'), findsOneWidget);
    expect(find.text('Collapse Folder'), findsOneWidget);
    expect(find.text('Hide Folder'), findsOneWidget);

    await tester.tap(find.text('Hide Folder'));
    await tester.pumpAndSettle();

    expect(hid, isTrue);
    expect(toggled, isFalse);
  });

  testWidgets('showHiddenFoldersDialog restores individual and all hidden folders', (
    tester,
  ) async {
    final hidden = {'/docs/Junk', '/downloads/Temp'};
    final restored = <String>[];
    bool clearedAll = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                showHiddenFoldersDialog(
                  context,
                  hiddenFolders: hidden,
                  onUnhideFolder: (path) async {
                    restored.add(path);
                    hidden.remove(path);
                  },
                  onUnhideAll: () async {
                    clearedAll = true;
                    hidden.clear();
                  },
                );
              },
              child: const Text('Manage'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();

    expect(find.text('Hidden Folders'), findsOneWidget);
    expect(find.text('Junk'), findsOneWidget);
    expect(find.text('Temp'), findsOneWidget);

    await tester.tap(find.text('Show').first);
    await tester.pumpAndSettle();

    expect(restored, ['/docs/Junk']);
    expect(find.text('Junk'), findsNothing);
    expect(find.text('Temp'), findsOneWidget);

    await tester.tap(find.text('Show All'));
    await tester.pumpAndSettle();

    expect(clearedAll, isTrue);
    expect(find.text('No hidden folders.'), findsOneWidget);
  });
}

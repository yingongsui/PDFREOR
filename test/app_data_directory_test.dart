import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreor/services/app_data_directory.dart';

void main() {
  test('AppDataDirectory creates missing support directory and resolves target file', () async {
    final root = Directory.systemTemp.createTempSync('pdfreor_appdata_');
    addTearDown(() => root.deleteSync(recursive: true));

    final supportDir = Directory('${root.path}/nested/support');
    expect(supportDir.existsSync(), isFalse);

    final resolved = await AppDataDirectory.resolveFile(
      'pdf_library.json',
      supportDirOverride: supportDir,
    );

    expect(supportDir.existsSync(), isTrue);
    expect(resolved.path, '${supportDir.path}/pdf_library.json');
  });
}

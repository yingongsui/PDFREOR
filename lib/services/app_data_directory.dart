import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Resolves internal app metadata files under Application Support.
class AppDataDirectory {
  AppDataDirectory._();

  static Future<File> resolveFile(
    String fileName, {
    Directory? supportDirOverride,
  }) async {
    final targetDir = supportDirOverride ?? await getApplicationSupportDirectory();
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    return File('${targetDir.path}${Platform.pathSeparator}$fileName');
  }
}

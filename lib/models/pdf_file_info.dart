import 'dart:io';
import 'package:path/path.dart' as p;

class PdfFileInfo {
  final String path;
  final String name;
  final int sizeInBytes;
  final DateTime lastModified;

  PdfFileInfo({
    required this.path,
    required this.name,
    required this.sizeInBytes,
    required this.lastModified,
  });

  factory PdfFileInfo.fromFile(File file) {
    int size = 0;
    DateTime modified = DateTime.now();
    try {
      final stat = file.statSync();
      size = stat.size;
      modified = stat.modified;
    } catch (_) {}

    final base = p.basename(file.path);
    final name = base.isNotEmpty ? base : 'document.pdf';
    return PdfFileInfo(
      path: file.path,
      name: name,
      sizeInBytes: size,
      lastModified: modified,
    );
  }

  String get formattedSize {
    if (sizeInBytes < 1024) {
      return '$sizeInBytes B';
    } else if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    } else if (sizeInBytes < 1024 * 1024 * 1024) {
      return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  String get parentDirectoryName => p.basename(p.dirname(path));

  String get parentDirectoryPath => p.dirname(path);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfFileInfo &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}


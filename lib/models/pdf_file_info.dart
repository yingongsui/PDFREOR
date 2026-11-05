import 'dart:io';

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

    final segments = file.path.split(Platform.pathSeparator).where((seg) => seg.isNotEmpty);
    final name = segments.isNotEmpty ? segments.last : 'document.pdf';
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

  String get parentDirectoryName {
    final segments = path.split(Platform.pathSeparator);
    if (segments.length >= 2) {
      return segments[segments.length - 2];
    }
    return '';
  }

  String get parentDirectoryPath {
    final idx = path.lastIndexOf(Platform.pathSeparator);
    if (idx != -1) {
      return path.substring(0, idx);
    }
    return '';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfFileInfo &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}


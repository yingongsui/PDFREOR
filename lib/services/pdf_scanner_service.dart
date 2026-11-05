import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/pdf_file_info.dart';

class PdfScannerService {
  static final PdfScannerService instance = PdfScannerService._internal();
  PdfScannerService._internal();

  /// Check whether appropriate storage permissions are granted.
  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) {
      return true;
    }

    // On Android 11+ (API 30+), check manageExternalStorage first
    final isManageGranted = await Permission.manageExternalStorage.isGranted;
    if (isManageGranted) return true;

    // For Android 10 and below, check general storage permission
    final isStorageGranted = await Permission.storage.isGranted;
    return isStorageGranted;
  }

  /// Request storage permissions. Returns true if granted.
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) {
      return true;
    }

    // Try requesting manageExternalStorage first on modern Android
    var status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

    // Fallback to storage permission
    status = await Permission.storage.request();
    return status.isGranted;
  }

  /// Open app settings page if permission was permanently denied.
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Scan storage for PDF files.
  /// If [progressCallback] is provided, it will be invoked with progress updates or found count.
  Future<List<PdfFileInfo>> scanStorage({
    void Function(String currentFolder, int foundCount)? progressCallback,
  }) async {
    final Map<String, PdfFileInfo> foundFiles = {};

    final directoriesToScan = <Directory>[];

    if (Platform.isAndroid) {
      final rootStorage = Directory('/storage/emulated/0');
      if (await rootStorage.exists()) {
        directoriesToScan.add(rootStorage);
      } else {
        // Fallbacks for unusual devices / paths
        final extDirs = await getExternalStorageDirectories();
        if (extDirs != null) {
          for (final dir in extDirs) {
            directoriesToScan.add(dir);
          }
        }
      }
    } else {
      // macOS, Windows, Linux, or iOS development / test
      final docDir = await getApplicationDocumentsDirectory();
      directoriesToScan.add(docDir);
      final downloadDir = await getDownloadsDirectory();
      if (downloadDir != null) {
        directoriesToScan.add(downloadDir);
      }
    }

    for (final dir in directoriesToScan) {
      await _scanDirectoryRecursively(dir, foundFiles, progressCallback);
    }

    final resultList = foundFiles.values.toList();
    // Default sort by last modified date descending (newest first)
    resultList.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return resultList;
  }

  /// Scan a specific user-selected directory.
  Future<List<PdfFileInfo>> scanCustomDirectory(
    String directoryPath, {
    void Function(String currentFolder, int foundCount)? progressCallback,
  }) async {
    final Map<String, PdfFileInfo> foundFiles = {};
    final dir = Directory(directoryPath);
    if (await dir.exists()) {
      await _scanDirectoryRecursively(dir, foundFiles, progressCallback);
    }
    final resultList = foundFiles.values.toList();
    resultList.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return resultList;
  }

  /// Let user manually pick one or more PDF files via system file picker.
  Future<List<PdfFileInfo>> pickPdfFiles() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (files.isNotEmpty) {
        final List<PdfFileInfo> list = [];
        for (final file in files) {
          if (file.path != null) {
            final ioFile = File(file.path!);
            if (await ioFile.exists()) {
              list.add(PdfFileInfo.fromFile(ioFile));
            }
          }
        }
        return list;
      }
    } catch (_) {}
    return [];
  }

  /// Let user pick a folder to scan.
  Future<String?> pickDirectory() async {
    try {
      return await FilePicker.getDirectoryPath();
    } catch (_) {
      return null;
    }
  }

  /// Safe recursive directory scanner with blacklists to avoid permission crashes and slow loops.
  Future<void> _scanDirectoryRecursively(
    Directory directory,
    Map<String, PdfFileInfo> foundFiles,
    void Function(String currentFolder, int foundCount)? progressCallback,
  ) async {
    final skipFolders = {
      'Android/data',
      'Android/obb',
      '.thumbnails',
      '.cache',
      '.trash',
      'node_modules',
      '.git',
    };

    final queue = <Directory>[directory];

    while (queue.isNotEmpty) {
      final currentDir = queue.removeAt(0);
      progressCallback?.call(currentDir.path, foundFiles.length);

      try {
        final entities = currentDir.listSync(followLinks: false);
        for (final entity in entities) {
          final path = entity.path;
          final basename = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '')
              : '';

          // Skip hidden files/directories (starting with .)
          if (basename.startsWith('.')) continue;

          if (entity is File) {
            if (path.toLowerCase().endsWith('.pdf')) {
              try {
                if (!foundFiles.containsKey(path)) {
                  foundFiles[path] = PdfFileInfo.fromFile(entity);
                }
              } catch (_) {}
            }
          } else if (entity is Directory) {
            // Check if directory should be skipped
            bool shouldSkip = false;
            for (final skip in skipFolders) {
              if (path.endsWith(skip) || path.contains('/$skip/')) {
                shouldSkip = true;
                break;
              }
            }
            if (!shouldSkip) {
              queue.add(entity);
            }
          }
        }
      } catch (_) {
        // Skip unreadable directories
      }
    }
  }
}

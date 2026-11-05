import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/pdf_file_info.dart';

class PdfScannerService {
  static final PdfScannerService instance = PdfScannerService._internal();
  PdfScannerService._internal();

  static const _channel = MethodChannel('com.yin.pdfreor/stylus');
  static const _libraryFileName = 'pdf_library.json';
  Set<String> _customFolders = {};
  Set<String> _importedFilePaths = {};
  Set<String> _collapsedFolders = {};
  String _folderSort = 'nameAsc';
  String _fileSort = 'dateDesc';
  bool _libraryLoaded = false;

  Future<void> _ensureLibraryLoaded() async {
    if (_libraryLoaded) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final file = File('${docDir.path}/$_libraryFileName');
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        if (map['customFolders'] is List) {
          _customFolders = (map['customFolders'] as List).map((e) => e.toString()).toSet();
        }
        if (map['importedFilePaths'] is List) {
          _importedFilePaths = (map['importedFilePaths'] as List).map((e) => e.toString()).toSet();
        }
        if (map['collapsedFolders'] is List) {
          _collapsedFolders = (map['collapsedFolders'] as List).map((e) => e.toString()).toSet();
        }
        if (map['folderSort'] is String) {
          _folderSort = map['folderSort'] as String;
        }
        if (map['fileSort'] is String) {
          _fileSort = map['fileSort'] as String;
        }
      }
    } catch (_) {}
    _libraryLoaded = true;
  }

  Future<void> _saveLibrary() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final file = File('${docDir.path}/$_libraryFileName');
      final data = {
        'customFolders': _customFolders.toList(),
        'importedFilePaths': _importedFilePaths.toList(),
        'collapsedFolders': _collapsedFolders.toList(),
        'folderSort': _folderSort,
        'fileSort': _fileSort,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<Set<String>> getCollapsedFolders() async {
    await _ensureLibraryLoaded();
    return Set.from(_collapsedFolders);
  }

  Future<void> setFolderCollapsed(String folderPath, bool isCollapsed) async {
    await _ensureLibraryLoaded();
    if (isCollapsed) {
      _collapsedFolders.add(folderPath);
    } else {
      _collapsedFolders.remove(folderPath);
    }
    await _saveLibrary();
  }

  Future<void> setAllFoldersCollapsed(Iterable<String> folderPaths, bool isCollapsed) async {
    await _ensureLibraryLoaded();
    if (isCollapsed) {
      _collapsedFolders.addAll(folderPaths);
    } else {
      _collapsedFolders.removeAll(folderPaths);
    }
    await _saveLibrary();
  }

  Future<String> getFolderSort() async {
    await _ensureLibraryLoaded();
    return _folderSort;
  }

  Future<void> setFolderSort(String sort) async {
    await _ensureLibraryLoaded();
    _folderSort = sort;
    await _saveLibrary();
  }

  Future<String> getFileSort() async {
    await _ensureLibraryLoaded();
    return _fileSort;
  }

  Future<void> setFileSort(String sort) async {
    await _ensureLibraryLoaded();
    _fileSort = sort;
    await _saveLibrary();
  }

  Future<void> addCustomFolder(String path) async {
    await _ensureLibraryLoaded();
    _customFolders.add(path);
    await _saveLibrary();
  }

  Future<void> removeCustomFolder(String path) async {
    await _ensureLibraryLoaded();
    _customFolders.remove(path);
    await _saveLibrary();
  }

  Future<void> addImportedFilePaths(Iterable<String> paths) async {
    await _ensureLibraryLoaded();
    _importedFilePaths.addAll(paths);
    await _saveLibrary();
  }

  Future<void> removeImportedFilePath(String path) async {
    await _ensureLibraryLoaded();
    _importedFilePaths.remove(path);
    await _saveLibrary();
  }

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

  /// Discover all storage volumes (Internal + SD Card + User Custom Folders).
  Future<List<Directory>> _getStorageDirectoriesToScan() async {
    final directoriesToScan = <Directory>[];

    if (Platform.isAndroid) {
      // 1. StorageManager volumes via native MethodChannel (includes internal and physical SD cards)
      try {
        final List<dynamic>? volumes =
            await _channel.invokeMethod<List<dynamic>>('getStorageVolumes');
        if (volumes != null) {
          for (final vol in volumes) {
            if (vol is String && vol.isNotEmpty) {
              final d = Directory(vol);
              if (await d.exists() && !directoriesToScan.any((x) => x.path == d.path)) {
                directoriesToScan.add(d);
              }
            }
          }
        }
      } catch (_) {}

      // 2. Primary emulated internal storage fallback if not already added
      final rootStorage = Directory('/storage/emulated/0');
      if (await rootStorage.exists() &&
          !directoriesToScan.any((d) => d.path == rootStorage.path)) {
        directoriesToScan.add(rootStorage);
      }

      // 3. Extract volume roots from external storage directories (e.g. SD cards)
      try {
        final extDirs = await getExternalStorageDirectories();
        if (extDirs != null) {
          for (final dir in extDirs) {
            final parts = dir.path.split('/Android/');
            if (parts.isNotEmpty) {
              final volumeRoot = Directory(parts[0]);
              if (await volumeRoot.exists() &&
                  !directoriesToScan.any((d) => d.path == volumeRoot.path)) {
                directoriesToScan.add(volumeRoot);
              }
            }
          }
        }
      } catch (_) {}
    } else {
      // macOS, Windows, Linux, iOS
      final docDir = await getApplicationDocumentsDirectory();
      directoriesToScan.add(docDir);
      final downloadDir = await getDownloadsDirectory();
      if (downloadDir != null) {
        directoriesToScan.add(downloadDir);
      }
    }

    // 4. User-added custom folders
    await _ensureLibraryLoaded();
    for (final folderPath in _customFolders) {
      final dir = Directory(folderPath);
      if (await dir.exists() && !directoriesToScan.any((d) => d.path == dir.path)) {
        directoriesToScan.add(dir);
      }
    }

    return directoriesToScan;
  }

  /// Scan storage for PDF files.
  /// If [progressCallback] is provided, it will be invoked with progress updates or found count.
  Future<List<PdfFileInfo>> scanStorage({
    void Function(String currentFolder, int foundCount)? progressCallback,
  }) async {
    final Map<String, PdfFileInfo> foundFiles = {};
    final directoriesToScan = await _getStorageDirectoriesToScan();

    for (final dir in directoriesToScan) {
      await _scanDirectoryRecursively(dir, foundFiles, progressCallback);
    }

    // Include manually imported files that still exist on disk
    await _ensureLibraryLoaded();
    for (final filePath in _importedFilePaths) {
      if (!foundFiles.containsKey(filePath)) {
        final file = File(filePath);
        if (await file.exists()) {
          try {
            foundFiles[filePath] = PdfFileInfo.fromFile(file);
          } catch (_) {}
        }
      }
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
    await addCustomFolder(directoryPath);
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
      try {
        progressCallback?.call(currentDir.path, foundFiles.length);
      } catch (_) {}

      try {
        final entities = currentDir.listSync(followLinks: false);
        for (final entity in entities) {
          try {
            final path = entity.path;
            final sep = Platform.pathSeparator;
            final lastIdx = path.lastIndexOf(sep);
            final basename = lastIdx != -1 ? path.substring(lastIdx + 1) : path;

            // Skip hidden files/directories (starting with .)
            if (basename.startsWith('.')) continue;

            if (entity is File) {
              if (path.toLowerCase().endsWith('.pdf')) {
                if (!foundFiles.containsKey(path)) {
                  foundFiles[path] = PdfFileInfo.fromFile(entity);
                }
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
          } catch (_) {
            // Ignore any individual file error (e.g. unreadable file or invalid path)
          }
        }
      } catch (_) {
        // Skip unreadable directories
      }
    }
  }
}

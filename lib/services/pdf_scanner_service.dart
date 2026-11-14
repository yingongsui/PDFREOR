import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/pdf_file_info.dart';
import 'atomic_file_store.dart';

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
  Future<void>? _loadFuture;

  Future<void> _ensureLibraryLoaded() {
    return _loadFuture ??= _loadLibraryFromDisk();
  }

  Future<void> _loadLibraryFromDisk() async {
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
      await AtomicFileStore.writeString(file, jsonEncode(data));
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

  Future<void> addImportedFilePaths(Iterable<String> paths) async {
    await _ensureLibraryLoaded();
    _importedFilePaths.addAll(paths);
    await _saveLibrary();
  }

  Future<void> removeImportedFilePaths(Iterable<String> paths) async {
    await _ensureLibraryLoaded();
    bool changed = false;
    for (final path in paths) {
      if (_importedFilePaths.remove(path)) {
        changed = true;
      }
    }
    if (changed) {
      await _saveLibrary();
    }
  }

  Future<void> renameImportedFilePath(String oldPath, String newPath) async {
    await _ensureLibraryLoaded();
    if (_importedFilePaths.remove(oldPath)) {
      _importedFilePaths.add(newPath);
      await _saveLibrary();
    }
  }

  /// Check whether appropriate storage permissions are granted.
  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) {
      return true;
    }

    final isManageGranted = await Permission.manageExternalStorage.isGranted;
    if (isManageGranted) return true;

    final isStorageGranted = await Permission.storage.isGranted;
    return isStorageGranted;
  }

  /// Request storage permissions. Returns true if granted.
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) {
      return true;
    }

    var status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

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

      final rootStorage = Directory('/storage/emulated/0');
      if (await rootStorage.exists() &&
          !directoriesToScan.any((d) => d.path == rootStorage.path)) {
        directoriesToScan.add(rootStorage);
      }

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
      final docDir = await getApplicationDocumentsDirectory();
      directoriesToScan.add(docDir);
      final downloadDir = await getDownloadsDirectory();
      if (downloadDir != null) {
        directoriesToScan.add(downloadDir);
      }
    }

    await _ensureLibraryLoaded();
    for (final folderPath in _customFolders) {
      final dir = Directory(folderPath);
      if (await dir.exists() && !directoriesToScan.any((d) => d.path == dir.path)) {
        directoriesToScan.add(dir);
      }
    }

    // Remove redundant child paths when a parent directory is already queued for recursive scan
    final sep = Platform.pathSeparator;
    final sortedPaths = directoriesToScan.map((d) => d.path).toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    final deduplicated = <Directory>[];
    for (final candidate in sortedPaths) {
      final coveredByParent = deduplicated.any((parent) {
        final pPath = parent.path;
        return candidate == pPath || candidate.startsWith('$pPath$sep');
      });
      if (!coveredByParent) {
        deduplicated.add(Directory(candidate));
      }
    }

    return deduplicated;
  }

  /// Scan storage for PDF files in a background isolate so UI stays 60/120fps smooth.
  Future<List<PdfFileInfo>> scanStorage() async {
    final directoriesToScan = await _getStorageDirectoriesToScan();
    await _ensureLibraryLoaded();

    final rootPaths = directoriesToScan.map((d) => d.path).toList();
    final importedSnapshot = _importedFilePaths.toList();

    return Isolate.run(
      () => _scanPathsInBackground(rootPaths, importedSnapshot),
    );
  }

  /// Scan a specific user-selected directory in a background isolate.
  Future<List<PdfFileInfo>> scanCustomDirectory(String directoryPath) async {
    await addCustomFolder(directoryPath);
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return [];

    return Isolate.run(
      () => _scanPathsInBackground([directoryPath], const []),
    );
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

  /// Pure isolate-safe recursive scanner using an O(1) `Queue<Directory>`.
  static List<PdfFileInfo> _scanPathsInBackground(
    List<String> rootPaths,
    List<String> importedPaths,
  ) {
    const skipFolders = {
      'Android/data',
      'Android/obb',
      '.thumbnails',
      '.cache',
      '.trash',
      'node_modules',
      '.git',
    };

    final Map<String, PdfFileInfo> foundFiles = {};
    final Queue<Directory> queue = Queue<Directory>();

    for (final root in rootPaths) {
      final d = Directory(root);
      if (d.existsSync()) {
        queue.add(d);
      }
    }

    final sep = Platform.pathSeparator;

    while (queue.isNotEmpty) {
      final currentDir = queue.removeFirst();
      try {
        final entities = currentDir.listSync(followLinks: false);
        for (final entity in entities) {
          try {
            final path = entity.path;
            final lastIdx = path.lastIndexOf(sep);
            final basename = lastIdx != -1 ? path.substring(lastIdx + 1) : path;

            // Skip hidden files/directories (starting with .)
            if (basename.startsWith('.')) continue;

            if (entity is File) {
              if (path.length > 4 && path.substring(path.length - 4).toLowerCase() == '.pdf') {
                if (!foundFiles.containsKey(path)) {
                  foundFiles[path] = PdfFileInfo.fromFile(entity);
                }
              }
            } else if (entity is Directory) {
              bool shouldSkip = false;
              for (final skip in skipFolders) {
                if (basename == skip ||
                    path.endsWith('$sep$skip') ||
                    path.contains('$sep$skip$sep')) {
                  shouldSkip = true;
                  break;
                }
              }
              if (!shouldSkip) {
                queue.add(entity);
              }
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    for (final filePath in importedPaths) {
      if (!foundFiles.containsKey(filePath)) {
        try {
          final file = File(filePath);
          if (file.existsSync()) {
            foundFiles[filePath] = PdfFileInfo.fromFile(file);
          }
        } catch (_) {}
      }
    }

    final resultList = foundFiles.values.toList();
    resultList.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return resultList;
  }
}

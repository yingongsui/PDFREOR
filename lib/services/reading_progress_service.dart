import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'pdf_export_service.dart';

/// Persists and restores the last visited 1-based page number per PDF file path.
class ReadingProgressService {
  static final ReadingProgressService instance = ReadingProgressService._();
  ReadingProgressService._();

  @visibleForTesting
  ReadingProgressService.forTesting();

  static const String _fileName = 'reading_progress.json';
  static const int _maxEntries = 1000;
  static const Duration _saveDebounce = Duration(milliseconds: 350);

  final LinkedHashMap<String, int> _pageByPath = LinkedHashMap<String, int>();
  final LinkedHashMap<String, double> _zoomByPath = LinkedHashMap<String, double>();
  Directory? _storageDirOverride;
  bool _initialized = false;
  bool _dirty = false;
  Timer? _debounceTimer;
  Future<void> _writeQueue = Future.value();

  Future<File> _getFile() async {
    final dir = _storageDirOverride ?? await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Loads persisted reading progress from disk.
  Future<void> init({Directory? storageDirOverride}) async {
    if (storageDirOverride != null) {
      _storageDirOverride = storageDirOverride;
    }
    if (_initialized) return;
    _initialized = true;

    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          final rawPages = decoded['pages'];
          if (rawPages is Map<String, dynamic>) {
            _pageByPath.clear();
            for (final entry in rawPages.entries) {
              final page = (entry.value as num?)?.toInt() ?? 1;
              if (entry.key.isNotEmpty && page > 1) {
                _pageByPath[entry.key] = page;
              }
            }
            while (_pageByPath.length > _maxEntries) {
              _pageByPath.remove(_pageByPath.keys.first);
            }
          }
          final rawZooms = decoded['zooms'];
          if (rawZooms is Map<String, dynamic>) {
            _zoomByPath.clear();
            for (final entry in rawZooms.entries) {
              final zoom = (entry.value as num?)?.toDouble();
              if (entry.key.isNotEmpty && zoom != null && zoom > 0.05 && zoom < 50.0) {
                _zoomByPath[entry.key] = zoom;
              }
            }
            while (_zoomByPath.length > _maxEntries) {
              _zoomByPath.remove(_zoomByPath.keys.first);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading reading progress: $e');
    }
  }

  /// Returns the last visited 1-based page number for [filePath], defaulting to 1.
  int getLastPage(String filePath) {
    if (filePath.isEmpty) return 1;
    final page = _pageByPath[filePath];
    if (page == null || page <= 1) return 1;
    return page;
  }

  /// Records [pageNumber] (1-based) as the last visited page for [filePath].
  void saveLastPage(String filePath, int pageNumber, {bool immediate = false}) {
    if (filePath.isEmpty) return;
    final normalized = pageNumber < 1 ? 1 : pageNumber;

    if (normalized <= 1) {
      if (_pageByPath.remove(filePath) == null) {
        return;
      }
    } else {
      final prev = _pageByPath.remove(filePath);
      _pageByPath[filePath] = normalized;
      while (_pageByPath.length > _maxEntries) {
        _pageByPath.remove(_pageByPath.keys.first);
      }
      if (prev == normalized) {
        return;
      }
    }

    _dirty = true;
    if (immediate) {
      flush().ignore();
    } else {
      _schedulePersist();
    }
  }

  /// Returns the last recorded zoom level for [filePath], or null if unset.
  double? getLastZoom(String filePath) {
    if (filePath.isEmpty) return null;
    return _zoomByPath[filePath];
  }

  /// Records [zoom] level for [filePath].
  void saveLastZoom(String filePath, double zoom, {bool immediate = false}) {
    if (filePath.isEmpty || zoom <= 0.05 || zoom > 50.0) return;
    final prev = _zoomByPath.remove(filePath);
    _zoomByPath[filePath] = zoom;
    while (_zoomByPath.length > _maxEntries) {
      _zoomByPath.remove(_zoomByPath.keys.first);
    }
    if (prev != null && (prev - zoom).abs() < 0.005) {
      return;
    }

    _dirty = true;
    if (immediate) {
      flush().ignore();
    } else {
      _schedulePersist();
    }
  }

  /// Migrates saved reading progress from [oldPath] to [newPath] on rename or move.
  void renamePath(String oldPath, String newPath) {
    if (oldPath.isEmpty || newPath.isEmpty || oldPath == newPath) return;
    final savedPage = _pageByPath.remove(oldPath);
    if (savedPage != null) {
      _pageByPath.remove(newPath);
      _pageByPath[newPath] = savedPage;
      _dirty = true;
    }
    final savedZoom = _zoomByPath.remove(oldPath);
    if (savedZoom != null) {
      _zoomByPath.remove(newPath);
      _zoomByPath[newPath] = savedZoom;
      _dirty = true;
    }
    if (_dirty) {
      _schedulePersist();
    }
  }

  /// Removes saved reading progress when a file is deleted.
  void removePath(String filePath) {
    if (filePath.isEmpty) return;
    bool changed = false;
    if (_pageByPath.remove(filePath) != null) changed = true;
    if (_zoomByPath.remove(filePath) != null) changed = true;
    if (changed) {
      _dirty = true;
      _schedulePersist();
    }
  }

  void _schedulePersist() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_saveDebounce, () {
      flush().ignore();
    });
  }

  /// Immediately writes any pending reading progress updates to disk.
  Future<void> flush() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (!_dirty) return _writeQueue;
    _dirty = false;

    final pagesSnapshot = Map<String, int>.from(_pageByPath);
    final zoomsSnapshot = Map<String, double>.from(_zoomByPath);
    _writeQueue = _writeQueue.then((_) async {
      try {
        final file = await _getFile();
        final payload = jsonEncode({
          'pages': pagesSnapshot,
          'zooms': zoomsSnapshot,
        });
        await PdfExportService.atomicWriteString(file, payload);
      } catch (e) {
        debugPrint('Error persisting reading progress: $e');
      }
    });
    return _writeQueue;
  }
}


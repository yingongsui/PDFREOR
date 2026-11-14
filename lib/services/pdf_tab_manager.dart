import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/pdf_file_info.dart';
import 'atomic_file_store.dart';
import 'reading_progress_service.dart';

/// Global manager for open PDF document tabs across the app with persistence.
class PdfTabManager extends ChangeNotifier {
  static final PdfTabManager instance = PdfTabManager._();
  PdfTabManager._();

  static const _fileName = 'open_tabs.json';
  final List<PdfFileInfo> _openTabs = [];
  late final UnmodifiableListView<PdfFileInfo> _openTabsView = UnmodifiableListView(_openTabs);
  int _activeIndex = 0;
  Future<void>? _initFuture;
  bool _mutatedSinceStart = false;

  List<PdfFileInfo> get openTabs => _openTabsView;
  int get activeIndex => _activeIndex;
  int get tabCount => _openTabs.length;

  PdfFileInfo? get activeFile =>
      (_openTabs.isNotEmpty && _activeIndex >= 0 && _activeIndex < _openTabs.length)
          ? _openTabs[_activeIndex]
          : null;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Initialize and load persisted tabs from disk.
  Future<void> init() {
    return _initFuture ??= _loadTabsFromDisk();
  }

  Future<void> _loadTabsFromDisk() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        final savedIndex = (map['activeIndex'] as num?)?.toInt() ?? 0;
        final rawList = map['tabs'] as List<dynamic>? ?? [];

        final restored = <PdfFileInfo>[];
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            final filePath = item['path'] as String? ?? '';
            if (filePath.isNotEmpty && await File(filePath).exists()) {
              restored.add(PdfFileInfo(
                path: filePath,
                name: item['name'] as String? ?? 'document.pdf',
                sizeInBytes: (item['sizeInBytes'] as num?)?.toInt() ?? 0,
                lastModified: item['lastModified'] != null
                    ? DateTime.fromMillisecondsSinceEpoch((item['lastModified'] as num).toInt())
                    : DateTime.now(),
              ));
            }
          }
        }

        if (restored.isNotEmpty) {
          if (!_mutatedSinceStart && _openTabs.isEmpty) {
            _openTabs.addAll(restored);
            _activeIndex = savedIndex.clamp(0, _openTabs.length - 1);
          } else {
            // Merge any restored tabs that aren't already open without clobbering active tab
            final existingPaths = _openTabs.map((t) => t.path).toSet();
            final missing = restored.where((t) => !existingPaths.contains(t.path)).toList();
            if (missing.isNotEmpty) {
              _openTabs.insertAll(0, missing);
              _activeIndex += missing.length;
            }
          }
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error restoring open tabs: $e');
    }
  }

  Future<void> _persistTabs() async {
    try {
      final file = await _getFile();
      final data = {
        'activeIndex': _activeIndex,
        'tabs': _openTabs
            .map((t) => {
                  'path': t.path,
                  'name': t.name,
                  'sizeInBytes': t.sizeInBytes,
                  'lastModified': t.lastModified.millisecondsSinceEpoch,
                })
            .toList(),
      };
      await AtomicFileStore.writeString(file, jsonEncode(data));
    } catch (e) {
      debugPrint('Error persisting open tabs: $e');
    }
  }

  void openTab(PdfFileInfo file) {
    _mutatedSinceStart = true;
    final existingIdx = _openTabs.indexWhere((t) => t.path == file.path);
    if (existingIdx != -1) {
      _activeIndex = existingIdx;
    } else {
      _openTabs.add(file);
      _activeIndex = _openTabs.length - 1;
    }
    notifyListeners();
    _persistTabs().ignore();
  }

  void openMultipleTabs(List<PdfFileInfo> files, {String? activePath}) {
    if (files.isEmpty) return;
    _mutatedSinceStart = true;
    for (final file in files) {
      final existingIdx = _openTabs.indexWhere((t) => t.path == file.path);
      if (existingIdx == -1) {
        _openTabs.add(file);
      }
    }
    final targetPath = activePath ?? files.first.path;
    final targetIdx = _openTabs.indexWhere((t) => t.path == targetPath);
    if (targetIdx != -1) {
      _activeIndex = targetIdx;
    }
    notifyListeners();
    _persistTabs().ignore();
  }

  void setActiveIndex(int index) {
    if (index >= 0 && index < _openTabs.length && index != _activeIndex) {
      _activeIndex = index;
      notifyListeners();
      _persistTabs().ignore();
    }
  }

  void closeTab(int index) {
    _mutatedSinceStart = true;
    if (index >= 0 && index < _openTabs.length) {
      _openTabs.removeAt(index);
      if (_activeIndex >= _openTabs.length) {
        _activeIndex = math.max(0, _openTabs.length - 1);
      }
      notifyListeners();
      _persistTabs().ignore();
    }
  }

  void closeTabByPath(String path) {
    final idx = _openTabs.indexWhere((t) => t.path == path);
    if (idx != -1) {
      closeTab(idx);
    }
  }

  void renameTab(String oldPath, PdfFileInfo newFile) {
    _mutatedSinceStart = true;
    ReadingProgressService.instance.renamePath(oldPath, newFile.path);
    final idx = _openTabs.indexWhere((t) => t.path == oldPath);
    if (idx != -1) {
      _openTabs[idx] = newFile;
      notifyListeners();
      _persistTabs().ignore();
    }
  }
}

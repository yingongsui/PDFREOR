import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'atomic_file_store.dart';

typedef VoidCallbackWithPath = void Function(String filePath);

class _PdfDocSession {
  final String filePath;
  Future<pdfrx.PdfDocument>? _docFuture;
  Future<void> _serialQueue = Future.value();
  Timer? _idleTimer;
  int _activeTasks = 0;
  bool _disposed = false;
  final VoidCallbackWithPath onIdleTimeout;

  _PdfDocSession(this.filePath, {required this.onIdleTimeout});

  Future<T?> runSerialized<T>(
    Future<T?> Function(pdfrx.PdfDocument doc) task,
  ) {
    final completer = Completer<T?>();
    _activeTasks++;
    _idleTimer?.cancel();

    _serialQueue = _serialQueue.then((_) async {
      if (_disposed) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      try {
        _docFuture ??= pdfrx.PdfDocument.openFile(filePath);
        final doc = await _docFuture!;
        if (_disposed) {
          if (!completer.isCompleted) completer.complete(null);
          return;
        }
        final res = await task(doc);
        if (!completer.isCompleted) completer.complete(res);
      } catch (_) {
        final brokenFuture = _docFuture;
        _docFuture = null;
        if (brokenFuture != null) {
          brokenFuture.then((d) => d.dispose()).catchError((_) {});
        }
        if (!completer.isCompleted) completer.complete(null);
      } finally {
        _activeTasks--;
        if (_activeTasks <= 0 && !_disposed) {
          _idleTimer?.cancel();
          _idleTimer = Timer(const Duration(seconds: 6), () {
            onIdleTimeout(filePath);
          });
        }
      }
    });

    return completer.future;
  }

  Future<void> close() {
    if (_disposed) return _serialQueue;
    _disposed = true;
    _idleTimer?.cancel();
    _serialQueue = _serialQueue.then((_) async {
      final future = _docFuture;
      _docFuture = null;
      if (future != null) {
        try {
          final doc = await future;
          await doc.dispose();
        } catch (_) {}
      }
    });
    return _serialQueue;
  }
}

class PdfThumbnailService {
  static final PdfThumbnailService instance = PdfThumbnailService._internal();
  PdfThumbnailService._internal();

  static const int _maxMemoryCacheEntries = 120;
  static const int _maxDiskCacheFiles = 400;

  final LinkedHashMap<String, Uint8List> _memoryCache =
      LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List?>> _inFlight = {};
  final Map<String, Set<String>> _diskCachePathsBySource = {};
  final Map<String, _PdfDocSession> _sessions = {};
  final Map<String, int> _generationByPath = {};
  int _globalEpoch = 0;
  Directory? _cacheDir;
  Future<void>? _initFuture;
  bool _pruneScheduled = false;

  Future<void> init() {
    if (_cacheDir != null) return Future.value();
    return _initFuture ??= _initCacheDir();
  }

  Future<void> _initCacheDir() async {
    try {
      final temp = await getTemporaryDirectory();
      final dir = Directory(p.join(temp.path, 'pdf_thumbnails'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;
    } finally {
      _initFuture = null;
    }
  }

  Uint8List? _getFromMemory(String key) {
    final val = _memoryCache.remove(key);
    if (val != null) {
      _memoryCache[key] = val;
    }
    return val;
  }

  void _putInMemory(String key, Uint8List bytes) {
    _memoryCache.remove(key);
    _memoryCache[key] = bytes;
    while (_memoryCache.length > _maxMemoryCacheEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  void _trackDiskCacheFile(String sourcePath, String cacheFilePath) {
    _diskCachePathsBySource
        .putIfAbsent(sourcePath, () => <String>{})
        .add(cacheFilePath);
  }

  _PdfDocSession _getSession(String filePath) {
    return _sessions.putIfAbsent(
      filePath,
      () => _PdfDocSession(
        filePath,
        onIdleTimeout: (path) {
          final session = _sessions.remove(path);
          session?.close();
        },
      ),
    );
  }

  String _getPathHash(String filePath) {
    return md5.convert(utf8.encode(filePath)).toString();
  }

  double _effectiveTargetWidth(int pageNumber, double targetWidth) {
    final clamped = targetWidth < 40.0 ? 40.0 : targetWidth;
    if (pageNumber == 1 && clamped < 300.0) {
      return 300.0;
    }
    return clamped;
  }

  bool _isEpochCurrent(String filePath, int pathEpoch, int globalEpoch) {
    return globalEpoch == _globalEpoch &&
        pathEpoch == (_generationByPath[filePath] ?? 0);
  }

  Future<Uint8List?> getThumbnail(
    String filePath, {
    int lastModifiedMillis = 0,
  }) {
    return getPageThumbnail(
      filePath,
      1,
      lastModifiedMillis: lastModifiedMillis,
      targetWidth: 300.0,
    );
  }

  Future<Uint8List?> getPageThumbnail(
    String filePath,
    int pageNumber, {
    int lastModifiedMillis = 0,
    double targetWidth = 240.0,
  }) async {
    final effectiveWidth = _effectiveTargetWidth(pageNumber, targetWidth);
    final widthKey = effectiveWidth.round();
    final memKey =
        '$filePath|$lastModifiedMillis:page:$pageNumber:w:$widthKey';

    final cachedMem = _getFromMemory(memKey);
    if (cachedMem != null) {
      return cachedMem;
    }

    final existingFlight = _inFlight[memKey];
    if (existingFlight != null) {
      return existingFlight;
    }

    final pathEpoch = _generationByPath[filePath] ?? 0;
    final globalEpoch = _globalEpoch;

    final future = _loadOrRenderPage(
      filePath: filePath,
      pageNumber: pageNumber,
      lastModifiedMillis: lastModifiedMillis,
      effectiveWidth: effectiveWidth,
      widthKey: widthKey,
      memKey: memKey,
      pathEpoch: pathEpoch,
      globalEpoch: globalEpoch,
    );
    _inFlight[memKey] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(memKey);
    }
  }

  Future<Uint8List?> _loadOrRenderPage({
    required String filePath,
    required int pageNumber,
    required int lastModifiedMillis,
    required double effectiveWidth,
    required int widthKey,
    required String memKey,
    required int pathEpoch,
    required int globalEpoch,
  }) async {
    try {
      await init();
      if (!_isEpochCurrent(filePath, pathEpoch, globalEpoch)) {
        return null;
      }

      final cacheDir = _cacheDir;
      if (cacheDir == null) return null;

      final pathHash = _getPathHash(filePath);
      final cacheFile = File(
        p.join(
          cacheDir.path,
          '${pathHash}_${lastModifiedMillis}_p${pageNumber}_w$widthKey.png',
        ),
      );
      _trackDiskCacheFile(filePath, cacheFile.path);

      if (await cacheFile.exists()) {
        final bytes = await cacheFile.readAsBytes();
        if (_isEpochCurrent(filePath, pathEpoch, globalEpoch)) {
          _putInMemory(memKey, bytes);
          return bytes;
        }
        return null;
      }

      final session = _getSession(filePath);
      return await session.runSerialized<Uint8List>((document) async {
        if (!_isEpochCurrent(filePath, pathEpoch, globalEpoch)) {
          return null;
        }
        if (pageNumber < 1 || pageNumber > document.pages.length) return null;
        final page = document.pages[pageNumber - 1];
        if (page.width <= 0 || page.height <= 0) return null;

        final renderWidth = effectiveWidth.round().clamp(1, 2048);
        final scale = renderWidth / page.width;
        final renderHeight = (page.height * scale).round().clamp(1, 4096);

        final pdfImage = await page.render(
          width: renderWidth,
          height: renderHeight,
          fullWidth: renderWidth.toDouble(),
          fullHeight: renderHeight.toDouble(),
          backgroundColor: 0xFFFFFFFF,
          annotationRenderingMode:
              pdfrx.PdfAnnotationRenderingMode.annotationAndForms,
        );
        if (pdfImage == null) return null;

        ui.Image? uiImage;
        try {
          uiImage = await pdfImage.createImage();
          final byteData = await uiImage.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (byteData == null) return null;
          final bytes = byteData.buffer.asUint8List();

          if (_isEpochCurrent(filePath, pathEpoch, globalEpoch)) {
            _putInMemory(memKey, bytes);
            unawaited(
              AtomicFileStore.writeBytes(cacheFile, bytes)
                  .then((_) => _scheduleDiskPrune())
                  .catchError((_) {}),
            );
            return bytes;
          }
          return null;
        } finally {
          uiImage?.dispose();
          pdfImage.dispose();
        }
      });
    } catch (_) {
      return null;
    }
  }

  void _scheduleDiskPrune() {
    if (_pruneScheduled || _cacheDir == null) return;
    _pruneScheduled = true;
    Future<void>.delayed(const Duration(seconds: 2), () async {
      try {
        await _pruneDiskCache();
      } finally {
        _pruneScheduled = false;
      }
    });
  }

  Future<void> _pruneDiskCache() async {
    final dir = _cacheDir;
    if (dir == null || !await dir.exists()) return;
    try {
      final entries = <({File file, DateTime modified})>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          if (entity.path.endsWith('.tmp')) {
            try {
              await entity.delete();
            } catch (_) {}
            continue;
          }
          try {
            final stat = await entity.stat();
            entries.add((file: entity, modified: stat.modified));
          } catch (_) {}
        }
      }
      if (entries.length <= _maxDiskCacheFiles) return;
      entries.sort((a, b) => a.modified.compareTo(b.modified));
      final toDeleteCount = entries.length - _maxDiskCacheFiles;
      for (int i = 0; i < toDeleteCount; i++) {
        try {
          await entries[i].file.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Clears both in-memory LRU cache, active native document sessions, and disk cache files.
  Future<void> clearAllCache() async {
    _globalEpoch++;
    _generationByPath.clear();
    _memoryCache.clear();
    _inFlight.clear();
    _diskCachePathsBySource.clear();

    final activeSessions = _sessions.values.toList();
    _sessions.clear();
    for (final s in activeSessions) {
      await s.close();
    }

    try {
      await init();
      if (_cacheDir != null && await _cacheDir!.exists()) {
        await for (final entity in _cacheDir!.list(followLinks: false)) {
          if (entity is File) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  void invalidate(String filePath) {
    _generationByPath[filePath] = (_generationByPath[filePath] ?? 0) + 1;
    _memoryCache.removeWhere((key, _) => key.startsWith('$filePath|'));
    _inFlight.removeWhere((key, _) => key.startsWith('$filePath|'));

    final session = _sessions.remove(filePath);
    session?.close();

    final diskPaths = _diskCachePathsBySource.remove(filePath);
    if (diskPaths != null) {
      for (final pth in diskPaths) {
        File(pth).delete().ignore();
      }
    }

    final prefix = '${_getPathHash(filePath)}_';
    final dir = _cacheDir;
    if (dir != null) {
      dir.list(followLinks: false).listen((entity) {
        if (entity is File && p.basename(entity.path).startsWith(prefix)) {
          entity.delete().ignore();
        }
      }, onError: (_) {});
    }
  }
}

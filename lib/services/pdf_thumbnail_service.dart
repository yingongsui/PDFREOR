import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

class _PdfDocSession {
  final String filePath;
  Future<PdfDocument>? _docFuture;
  Future<void> _serialQueue = Future.value();
  Timer? _idleTimer;
  int _activeTasks = 0;
  bool _disposed = false;
  final VoidCallbackWithPath onIdleTimeout;

  _PdfDocSession(this.filePath, {required this.onIdleTimeout});

  Future<T?> runSerialized<T>(Future<T?> Function(PdfDocument doc) task) {
    final completer = Completer<T?>();
    _activeTasks++;
    _idleTimer?.cancel();

    _serialQueue = _serialQueue.then((_) async {
      if (_disposed) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      try {
        _docFuture ??= PdfDocument.openFile(filePath);
        final doc = await _docFuture!;
        if (_disposed) {
          if (!completer.isCompleted) completer.complete(null);
          return;
        }
        final res = await task(doc);
        if (!completer.isCompleted) completer.complete(res);
      } catch (_) {
        // Reset broken document handle on error
        final brokenFuture = _docFuture;
        _docFuture = null;
        if (brokenFuture != null) {
          brokenFuture.then((d) => d.close()).catchError((_) {});
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

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _idleTimer?.cancel();
    final future = _docFuture;
    _docFuture = null;
    if (future != null) {
      try {
        final doc = await future;
        await doc.close();
      } catch (_) {}
    }
  }
}

typedef VoidCallbackWithPath = void Function(String filePath);

class PdfThumbnailService {
  static final PdfThumbnailService instance = PdfThumbnailService._internal();
  PdfThumbnailService._internal();

  static const int _maxMemoryCacheEntries = 120;

  final LinkedHashMap<String, Uint8List> _memoryCache = LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List?>> _inFlight = {};
  final Map<String, Set<String>> _diskCachePathsBySource = {};
  final Map<String, _PdfDocSession> _sessions = {};
  Directory? _cacheDir;

  Future<void> init() async {
    if (_cacheDir == null) {
      final temp = await getTemporaryDirectory();
      _cacheDir = Directory(p.join(temp.path, 'pdf_thumbnails'));
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
    }
  }

  Uint8List? _getFromMemory(String key) {
    final val = _memoryCache.remove(key);
    if (val != null) {
      // Re-insert as most recently used
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
    _diskCachePathsBySource.putIfAbsent(sourcePath, () => <String>{}).add(cacheFilePath);
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

  Future<Uint8List?> getThumbnail(String filePath, {int lastModifiedMillis = 0}) {
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
    final memKey = '$filePath|$lastModifiedMillis:page:$pageNumber';
    final cachedMem = _getFromMemory(memKey);
    if (cachedMem != null) {
      return cachedMem;
    }

    final existingFlight = _inFlight[memKey];
    if (existingFlight != null) {
      return existingFlight;
    }

    final future = _loadOrRenderPage(
      filePath: filePath,
      pageNumber: pageNumber,
      lastModifiedMillis: lastModifiedMillis,
      targetWidth: targetWidth,
      memKey: memKey,
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
    required double targetWidth,
    required String memKey,
  }) async {
    try {
      await init();
      final pathHash = _getPathHash(filePath);
      final cacheFile = File(
        p.join(_cacheDir!.path, '${pathHash}_${lastModifiedMillis}_p$pageNumber.jpg'),
      );
      _trackDiskCacheFile(filePath, cacheFile.path);

      if (await cacheFile.exists()) {
        final bytes = await cacheFile.readAsBytes();
        _putInMemory(memKey, bytes);
        return bytes;
      }

      final session = _getSession(filePath);
      return await session.runSerialized<Uint8List>((document) async {
        if (pageNumber < 1 || pageNumber > document.pagesCount) return null;
        final page = await document.getPage(pageNumber);
        try {
          final effectiveWidth = pageNumber == 1 && targetWidth < 300.0 ? 300.0 : targetWidth;
          final scale = effectiveWidth / page.width;
          final targetHeight = page.height * scale;

          final pageImage = await page.render(
            width: effectiveWidth,
            height: targetHeight,
            format: PdfPageImageFormat.jpeg,
            quality: pageNumber == 1 ? 85 : 80,
          );

          if (pageImage != null) {
            final bytes = pageImage.bytes;
            _putInMemory(memKey, bytes);
            cacheFile.writeAsBytes(bytes).ignore();
            return bytes;
          }
        } finally {
          await page.close();
        }
        return null;
      });
    } catch (_) {
      return null;
    }
  }

  /// Clears both in-memory LRU cache, active native document sessions, and disk cache files.
  Future<void> clearAllCache() async {
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

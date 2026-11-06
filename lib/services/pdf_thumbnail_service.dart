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

  String _getCacheKey(String keyInput, int lastModifiedMillis) {
    final input = '$keyInput-$lastModifiedMillis';
    return md5.convert(utf8.encode(input)).toString();
  }

  Future<Uint8List?> getThumbnail(String filePath, {int lastModifiedMillis = 0}) async {
    final memKey = '$filePath|$lastModifiedMillis';
    final cachedMem = _getFromMemory(memKey);
    if (cachedMem != null) {
      return cachedMem;
    }

    try {
      await init();
      final cacheKey = _getCacheKey(filePath, lastModifiedMillis);
      final cacheFile = File(p.join(_cacheDir!.path, '$cacheKey.jpg'));
      _trackDiskCacheFile(filePath, cacheFile.path);

      if (await cacheFile.exists()) {
        final bytes = await cacheFile.readAsBytes();
        _putInMemory(memKey, bytes);
        return bytes;
      }

      final session = _getSession(filePath);
      return await session.runSerialized<Uint8List>((document) async {
        if (document.pagesCount < 1) return null;
        final page = await document.getPage(1);
        try {
          const targetWidth = 300.0;
          final scale = targetWidth / page.width;
          final targetHeight = page.height * scale;

          final pageImage = await page.render(
            width: targetWidth,
            height: targetHeight,
            format: PdfPageImageFormat.jpeg,
            quality: 85,
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
      // PDF might be encrypted or corrupted
    }

    return null;
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

    try {
      await init();
      final cacheKey = _getCacheKey('$filePath-page-$pageNumber', lastModifiedMillis);
      final cacheFile = File(p.join(_cacheDir!.path, '$cacheKey.jpg'));
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
          final scale = targetWidth / page.width;
          final targetHeight = page.height * scale;

          final pageImage = await page.render(
            width: targetWidth,
            height: targetHeight,
            format: PdfPageImageFormat.jpeg,
            quality: 80,
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

  void clearMemoryCache() {
    _memoryCache.clear();
  }

  /// Clears both in-memory LRU cache, active native document sessions, and disk cache files.
  Future<void> clearAllCache() async {
    _memoryCache.clear();
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

    final session = _sessions.remove(filePath);
    session?.close();

    final diskPaths = _diskCachePathsBySource.remove(filePath);
    if (diskPaths != null) {
      for (final pth in diskPaths) {
        try {
          final f = File(pth);
          if (f.existsSync()) {
            f.deleteSync();
          }
        } catch (_) {}
      }
    }
  }
}

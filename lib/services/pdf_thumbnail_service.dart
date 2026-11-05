import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

class PdfThumbnailService {
  static final PdfThumbnailService instance = PdfThumbnailService._internal();
  PdfThumbnailService._internal();

  final Map<String, Uint8List> _memoryCache = {};
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

  String _getCacheKey(String filePath, int lastModifiedMillis) {
    final input = '$filePath-$lastModifiedMillis';
    return md5.convert(utf8.encode(input)).toString();
  }

  Future<Uint8List?> getThumbnail(String filePath, {int lastModifiedMillis = 0}) async {
    // 1. Check memory cache
    if (_memoryCache.containsKey(filePath)) {
      return _memoryCache[filePath];
    }

    try {
      await init();
      final cacheKey = _getCacheKey(filePath, lastModifiedMillis);
      final cacheFile = File(p.join(_cacheDir!.path, '$cacheKey.jpg'));

      // 2. Check disk cache
      if (await cacheFile.exists()) {
        final bytes = await cacheFile.readAsBytes();
        _memoryCache[filePath] = bytes;
        return bytes;
      }

      // 3. Render page 1 using pdfx
      final document = await PdfDocument.openFile(filePath);
      try {
        final page = await document.getPage(1);
        try {
          // Render with reasonable resolution for thumbnails
          final scale = 300.0 / page.width;
          final targetWidth = 300.0;
          final targetHeight = page.height * scale;

          final pageImage = await page.render(
            width: targetWidth,
            height: targetHeight,
            format: PdfPageImageFormat.jpeg,
            quality: 85,
          );

          if (pageImage != null) {
            final bytes = pageImage.bytes;
            _memoryCache[filePath] = bytes;
            // save to disk cache in background
            cacheFile.writeAsBytes(bytes).ignore();
            return bytes;
          }
        } finally {
          await page.close();
        }
      } finally {
        await document.close();
      }
    } catch (_) {
      // PDF might be encrypted or corrupted
    }

    return null;
  }

  void clearMemoryCache() {
    _memoryCache.clear();
  }

  Future<Uint8List?> getPageThumbnail(
    String filePath,
    int pageNumber, {
    int lastModifiedMillis = 0,
    double targetWidth = 240.0,
  }) async {
    final memKey = '$filePath:$pageNumber';
    if (_memoryCache.containsKey(memKey)) {
      return _memoryCache[memKey];
    }

    try {
      await init();
      final cacheKey = _getCacheKey('$filePath-page-$pageNumber', lastModifiedMillis);
      final cacheFile = File(p.join(_cacheDir!.path, '$cacheKey.jpg'));

      if (await cacheFile.exists()) {
        final bytes = await cacheFile.readAsBytes();
        _memoryCache[memKey] = bytes;
        return bytes;
      }

      final document = await PdfDocument.openFile(filePath);
      try {
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
            _memoryCache[memKey] = bytes;
            cacheFile.writeAsBytes(bytes).ignore();
            return bytes;
          }
        } finally {
          await page.close();
        }
      } finally {
        await document.close();
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  void invalidate(String filePath) {
    _memoryCache.remove(filePath);
    _memoryCache.removeWhere((key, _) => key.startsWith('$filePath:'));
  }
}


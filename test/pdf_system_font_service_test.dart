import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfreor/services/pdf_system_font_service.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test('MacOsSystemFontResolver maps macOS CJK and Western fonts accurately', () async {
    final tempDir = await Directory.systemTemp.createTemp('macos_fonts_mock_');
    try {
      for (final fileName in const [
        'Hiragino Sans GB.ttc',
        'Songti.ttc',
        'Arial.ttf',
        'Arial Bold.ttf',
        'Times New Roman Italic.ttf',
        'Menlo.ttc',
      ]) {
        await File(p.join(tempDir.path, fileName)).writeAsBytes(const [0, 1, 2, 3]);
      }

      final resolver = MacOsSystemFontResolver(searchDirectories: [tempDir.path]);
      const ctx = PdfFontResolveContext();

      final jpGothic = resolver.resolve(
        const PdfFontQuery(
          face: 'MS-PGothic',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.shiftJis,
          pitchFamily: 0,
        ),
        ctx,
      );
      expect(jpGothic?.fontFilePath, p.join(tempDir.path, 'Hiragino Sans GB.ttc'));

      final cnSong = resolver.resolve(
        const PdfFontQuery(
          face: 'SimSun',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.gb2312,
          pitchFamily: 16,
        ),
        ctx,
      );
      expect(cnSong?.fontFilePath, p.join(tempDir.path, 'Songti.ttc'));

      final westBold = resolver.resolve(
        const PdfFontQuery(
          face: 'Helvetica-Bold',
          weight: 700,
          isItalic: false,
          charset: PdfFontCharset.ansi,
          pitchFamily: 0,
        ),
        ctx,
      );
      expect(westBold?.fontFilePath, p.join(tempDir.path, 'Arial Bold.ttf'));

      final westSerifItalic = resolver.resolve(
        const PdfFontQuery(
          face: 'TimesNewRomanPS-ItalicMT',
          weight: 400,
          isItalic: true,
          charset: PdfFontCharset.ansi,
          pitchFamily: 16,
        ),
        ctx,
      );
      expect(
        westSerifItalic?.fontFilePath,
        p.join(tempDir.path, 'Times New Roman Italic.ttf'),
      );

      final westMono = resolver.resolve(
        const PdfFontQuery(
          face: 'CourierNewPSMT',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.ansi,
          pitchFamily: 1,
        ),
        ctx,
      );
      expect(westMono?.fontFilePath, p.join(tempDir.path, 'Menlo.ttc'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('LinuxSystemFontResolver maps Ubuntu CJK and Western fonts accurately', () async {
    final tempDir = await Directory.systemTemp.createTemp('linux_fonts_mock_');
    try {
      for (final fileName in const [
        'NotoSansCJK-Regular.ttc',
        'NotoSerifCJK-Regular.ttc',
        'LiberationSans-Bold.ttf',
        'LiberationSerif-Italic.ttf',
        'LiberationMono-Regular.ttf',
      ]) {
        await File(p.join(tempDir.path, fileName)).writeAsBytes(const [0, 1, 2, 3]);
      }

      final resolver = LinuxSystemFontResolver(searchDirectories: [tempDir.path]);
      const ctx = PdfFontResolveContext();

      final jpGothic = resolver.resolve(
        const PdfFontQuery(
          face: 'MS-PGothic',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.shiftJis,
          pitchFamily: 0,
        ),
        ctx,
      );
      expect(jpGothic?.fontFilePath, p.join(tempDir.path, 'NotoSansCJK-Regular.ttc'));

      final cnSong = resolver.resolve(
        const PdfFontQuery(
          face: 'SimSun',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.gb2312,
          pitchFamily: 16,
        ),
        ctx,
      );
      expect(cnSong?.fontFilePath, p.join(tempDir.path, 'NotoSerifCJK-Regular.ttc'));

      final westBold = resolver.resolve(
        const PdfFontQuery(
          face: 'Helvetica-Bold',
          weight: 700,
          isItalic: false,
          charset: PdfFontCharset.ansi,
          pitchFamily: 0,
        ),
        ctx,
      );
      expect(westBold?.fontFilePath, p.join(tempDir.path, 'LiberationSans-Bold.ttf'));

      final westSerifItalic = resolver.resolve(
        const PdfFontQuery(
          face: 'TimesNewRomanPS-ItalicMT',
          weight: 400,
          isItalic: true,
          charset: PdfFontCharset.ansi,
          pitchFamily: 16,
        ),
        ctx,
      );
      expect(
        westSerifItalic?.fontFilePath,
        p.join(tempDir.path, 'LiberationSerif-Italic.ttf'),
      );

      final westMono = resolver.resolve(
        const PdfFontQuery(
          face: 'CourierNewPSMT',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.ansi,
          pitchFamily: 1,
        ),
        ctx,
      );
      expect(westMono?.fontFilePath, p.join(tempDir.path, 'LiberationMono-Regular.ttf'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('WindowsSystemFontResolver maps Windows CJK and Western fonts accurately', () async {
    final tempDir = await Directory.systemTemp.createTemp('windows_fonts_mock_');
    try {
      for (final fileName in const [
        'msyh.ttc',
        'simsun.ttc',
        'arialbd.ttf',
        'timesi.ttf',
        'consola.ttf',
      ]) {
        await File(p.join(tempDir.path, fileName)).writeAsBytes(const [0, 1, 2, 3]);
      }

      final resolver = WindowsSystemFontResolver(searchDirectories: [tempDir.path]);
      const ctx = PdfFontResolveContext();

      final cnSans = resolver.resolve(
        const PdfFontQuery(
          face: 'SimHei',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.gb2312,
          pitchFamily: 0,
        ),
        ctx,
      );
      expect(cnSans?.fontFilePath, p.join(tempDir.path, 'msyh.ttc'));

      final cnSerif = resolver.resolve(
        const PdfFontQuery(
          face: 'SimSun',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.gb2312,
          pitchFamily: 16,
        ),
        ctx,
      );
      expect(cnSerif?.fontFilePath, p.join(tempDir.path, 'simsun.ttc'));

      final westBold = resolver.resolve(
        const PdfFontQuery(
          face: 'Helvetica-Bold',
          weight: 700,
          isItalic: false,
          charset: PdfFontCharset.ansi,
          pitchFamily: 0,
        ),
        ctx,
      );
      expect(westBold?.fontFilePath, p.join(tempDir.path, 'arialbd.ttf'));

      final westSerifItalic = resolver.resolve(
        const PdfFontQuery(
          face: 'TimesNewRomanPS-ItalicMT',
          weight: 400,
          isItalic: true,
          charset: PdfFontCharset.ansi,
          pitchFamily: 16,
        ),
        ctx,
      );
      expect(westSerifItalic?.fontFilePath, p.join(tempDir.path, 'timesi.ttf'));

      final westMono = resolver.resolve(
        const PdfFontQuery(
          face: 'CourierNewPSMT',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.ansi,
          pitchFamily: 1,
        ),
        ctx,
      );
      expect(westMono?.fontFilePath, p.join(tempDir.path, 'consola.ttf'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}


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
}


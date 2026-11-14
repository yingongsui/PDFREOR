import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfreor/services/pdf_system_font_service.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test('AndroidSystemFontResolver maps CJK, CID, localized, and Western fonts accurately', () async {
    final tempDir = await Directory.systemTemp.createTemp('android_fonts_mock_');
    try {
      for (final fileName in const [
        'NotoSansCJK-Regular.ttc',
        'NotoSerifCJK-Regular.ttc',
        'Roboto-Regular.ttf',
        'Roboto-Bold.ttf',
        'NotoSerif-Italic.ttf',
        'DroidSansMono.ttf',
        'NotoNaskhArabic-Regular.ttf',
      ]) {
        await File(p.join(tempDir.path, fileName)).writeAsBytes(const [0, 1, 2, 3]);
      }

      final resolver = AndroidSystemFontResolver(searchDirectories: [tempDir.path]);
      const ctx = PdfFontResolveContext();

      // 1. Japanese Shift-JIS sans-serif -> NotoSansCJK-Regular.ttc
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
      expect(jpGothic?.targetFace, 'MS-PGothic');

      // 2. Japanese Shift-JIS Mincho / Serif -> NotoSerifCJK-Regular.ttc
      final jpMincho = resolver.resolve(
        const PdfFontQuery(
          face: 'HeiseiMin-W3-90ms-RKSJ-H',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.shiftJis,
          pitchFamily: 16,
        ),
        ctx,
      );
      expect(jpMincho?.fontFilePath, p.join(tempDir.path, 'NotoSerifCJK-Regular.ttc'));

      // 3. Simplified Chinese subsetted font -> NotoSansCJK-Regular.ttc
      final cnSubset = resolver.resolve(
        const PdfFontQuery(
          face: 'BCDEEE+FZLTHJW--GB1-0',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.gb2312,
          pitchFamily: 0,
        ),
        ctx,
      );
      expect(cnSubset?.fontFilePath, p.join(tempDir.path, 'NotoSansCJK-Regular.ttc'));
      expect(cnSubset?.targetFace, 'BCDEEE+FZLTHJW--GB1-0');

      // 4. Localized non-ASCII Songti face name with ANSI/default charset -> NotoSerifCJK-Regular.ttc
      final localizedSong = resolver.resolve(
        const PdfFontQuery(
          face: '\u5b8b\u4f53',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.default_,
          pitchFamily: 0,
        ),
        ctx,
      );
      expect(localizedSong?.fontFilePath, p.join(tempDir.path, 'NotoSerifCJK-Regular.ttc'));

      // 5. Generic unembedded CIDFont+F1 with default charset -> NotoSansCJK-Regular.ttc
      final genericCid = resolver.resolve(
        const PdfFontQuery(
          face: 'CIDFont+F1',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.default_,
          pitchFamily: 0,
        ),
        ctx,
      );
      expect(genericCid?.fontFilePath, p.join(tempDir.path, 'NotoSansCJK-Regular.ttc'));

      // 6. Western styled fonts -> Roboto-Bold, NotoSerif-Italic, DroidSansMono
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
      expect(westBold?.fontFilePath, p.join(tempDir.path, 'Roboto-Bold.ttf'));

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
      expect(westSerifItalic?.fontFilePath, p.join(tempDir.path, 'NotoSerif-Italic.ttf'));

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
      expect(westMono?.fontFilePath, p.join(tempDir.path, 'DroidSansMono.ttf'));

      // 7. CJK SansSerif query must not match serif substring falsely
      final cjkSansSerif = resolver.resolve(
        const PdfFontQuery(
          face: 'SimHei-SansSerif',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.gb2312,
          pitchFamily: 0,
        ),
        ctx,
      );
      expect(cjkSansSerif?.fontFilePath, p.join(tempDir.path, 'NotoSansCJK-Regular.ttc'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}


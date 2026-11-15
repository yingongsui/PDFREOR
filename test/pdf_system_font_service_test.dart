import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfreor/services/pdf_system_font_service.dart';
import 'package:pdfrx/pdfrx.dart';

Future<void> _verifySystemFontResolver({
  required String tempPrefix,
  required List<String> mockFiles,
  required SystemFontResolver Function(String dirPath) createResolver,
  required PdfFontQuery cjkSansQuery,
  required String expectedCjkSans,
  required String expectedCjkSerif,
  required String expectedWestBold,
  required String expectedWestSerifItalic,
  required String expectedWestMono,
}) async {
  final tempDir = await Directory.systemTemp.createTemp(tempPrefix);
  try {
    for (final fileName in mockFiles) {
      await File(p.join(tempDir.path, fileName)).writeAsBytes(const [0, 1, 2, 3]);
    }

    final resolver = createResolver(tempDir.path);
    const ctx = PdfFontResolveContext();

    expect(resolver.resolve(cjkSansQuery, ctx)?.fontFilePath, p.join(tempDir.path, expectedCjkSans));
    expect(
      resolver.resolve(
        const PdfFontQuery(
          face: 'SimSun',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.gb2312,
          pitchFamily: 16,
        ),
        ctx,
      )?.fontFilePath,
      p.join(tempDir.path, expectedCjkSerif),
    );
    expect(
      resolver.resolve(
        const PdfFontQuery(
          face: 'Helvetica-Bold',
          weight: 700,
          isItalic: false,
          charset: PdfFontCharset.ansi,
          pitchFamily: 0,
        ),
        ctx,
      )?.fontFilePath,
      p.join(tempDir.path, expectedWestBold),
    );
    expect(
      resolver.resolve(
        const PdfFontQuery(
          face: 'TimesNewRomanPS-ItalicMT',
          weight: 400,
          isItalic: true,
          charset: PdfFontCharset.ansi,
          pitchFamily: 16,
        ),
        ctx,
      )?.fontFilePath,
      p.join(tempDir.path, expectedWestSerifItalic),
    );
    expect(
      resolver.resolve(
        const PdfFontQuery(
          face: 'CourierNewPSMT',
          weight: 400,
          isItalic: false,
          charset: PdfFontCharset.ansi,
          pitchFamily: 1,
        ),
        ctx,
      )?.fontFilePath,
      p.join(tempDir.path, expectedWestMono),
    );
  } finally {
    await tempDir.delete(recursive: true);
  }
}

void main() {
  test('MacOsSystemFontResolver maps macOS CJK and Western fonts accurately', () async {
    await _verifySystemFontResolver(
      tempPrefix: 'macos_fonts_mock_',
      mockFiles: const [
        'Hiragino Sans GB.ttc',
        'Songti.ttc',
        'Arial.ttf',
        'Arial Bold.ttf',
        'Times New Roman Italic.ttf',
        'Menlo.ttc',
      ],
      createResolver: (dir) => MacOsSystemFontResolver(searchDirectories: [dir]),
      cjkSansQuery: const PdfFontQuery(
        face: 'MS-PGothic',
        weight: 400,
        isItalic: false,
        charset: PdfFontCharset.shiftJis,
        pitchFamily: 0,
      ),
      expectedCjkSans: 'Hiragino Sans GB.ttc',
      expectedCjkSerif: 'Songti.ttc',
      expectedWestBold: 'Arial Bold.ttf',
      expectedWestSerifItalic: 'Times New Roman Italic.ttf',
      expectedWestMono: 'Menlo.ttc',
    );
  });

  test('LinuxSystemFontResolver maps Ubuntu CJK and Western fonts accurately', () async {
    await _verifySystemFontResolver(
      tempPrefix: 'linux_fonts_mock_',
      mockFiles: const [
        'NotoSansCJK-Regular.ttc',
        'NotoSerifCJK-Regular.ttc',
        'LiberationSans-Bold.ttf',
        'LiberationSerif-Italic.ttf',
        'LiberationMono-Regular.ttf',
      ],
      createResolver: (dir) => LinuxSystemFontResolver(searchDirectories: [dir]),
      cjkSansQuery: const PdfFontQuery(
        face: 'MS-PGothic',
        weight: 400,
        isItalic: false,
        charset: PdfFontCharset.shiftJis,
        pitchFamily: 0,
      ),
      expectedCjkSans: 'NotoSansCJK-Regular.ttc',
      expectedCjkSerif: 'NotoSerifCJK-Regular.ttc',
      expectedWestBold: 'LiberationSans-Bold.ttf',
      expectedWestSerifItalic: 'LiberationSerif-Italic.ttf',
      expectedWestMono: 'LiberationMono-Regular.ttf',
    );
  });

  test('WindowsSystemFontResolver maps Windows CJK and Western fonts accurately', () async {
    await _verifySystemFontResolver(
      tempPrefix: 'windows_fonts_mock_',
      mockFiles: const [
        'msyh.ttc',
        'simsun.ttc',
        'arialbd.ttf',
        'timesi.ttf',
        'consola.ttf',
      ],
      createResolver: (dir) => WindowsSystemFontResolver(searchDirectories: [dir]),
      cjkSansQuery: const PdfFontQuery(
        face: 'SimHei',
        weight: 400,
        isItalic: false,
        charset: PdfFontCharset.gb2312,
        pitchFamily: 0,
      ),
      expectedCjkSans: 'msyh.ttc',
      expectedCjkSerif: 'simsun.ttc',
      expectedWestBold: 'arialbd.ttf',
      expectedWestSerifItalic: 'timesi.ttf',
      expectedWestMono: 'consola.ttf',
    );
  });

  test('viewerFontManager stays null until font manager preparation succeeds', () {
    // Accessing viewerFontManager before init() must not trigger or return an
    // unprepared PdfFontManager that could stall PdfViewer document loading.
    expect(PdfSystemFontService.instance.viewerFontManager, isNull);
  });
}


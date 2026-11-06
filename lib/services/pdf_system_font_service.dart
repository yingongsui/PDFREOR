import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Resolves missing PDF fonts (especially non-embedded CJK CID/legacy-encoded fonts
/// and international scripts) to built-in Android system font files without copying
/// multi-megabyte TTC/TTF collections into app storage.
class AndroidSystemFontResolver implements PdfFontResolver {
  AndroidSystemFontResolver({List<String>? searchDirectories})
      : _searchDirectories = searchDirectories ?? _defaultAndroidFontDirs;

  static const List<String> _defaultAndroidFontDirs = [
    '/system/fonts',
    '/product/fonts',
    '/system/product/fonts',
    '/apex/com.android.i18n/etc/fonts',
    '/vendor/fonts',
  ];

  static const List<String> _cjkSansFiles = [
    'NotoSansCJK-Regular.ttc',
    'NotoSansCJKjp-Regular.otf',
    'NotoSansCJKsc-Regular.otf',
    'NotoSansCJKtc-Regular.otf',
    'NotoSansCJKkr-Regular.otf',
    'DroidSansFallbackFull.ttf',
    'DroidSansFallback.ttf',
    'SECMonoCJK.ttf',
  ];

  static const List<String> _cjkSerifFiles = [
    'NotoSerifCJK-Regular.ttc',
    'NotoSerifCJKjp-Regular.otf',
    'NotoSerifCJKsc-Regular.otf',
    'NotoSerifCJKtc-Regular.otf',
    'NotoSerifCJKkr-Regular.otf',
  ];

  static const List<String> _cjkKeywords = [
    'cjk',
    'sourcehan',
    'mincho',
    'gothic',
    'meiryo',
    'yugothic',
    'yumincho',
    'heisei',
    'kozmin',
    'kozgo',
    'ryumin',
    'gothicbbb',
    'hiragino',
    'hirakaku',
    'hiramin',
    'ipaex',
    'ipag',
    'ipam',
    'bizud',
    'maru',
    'kyokasho',
    'hgmaru',
    'hggothic',
    'hgmincho',
    'simsun',
    'nsimsun',
    'simhei',
    'yahei',
    'stsong',
    'stheiti',
    'stkaiti',
    'stfangsong',
    'adobesong',
    'adobeheiti',
    'adobeming',
    'adobekaiti',
    'adobefangsong',
    'adobemyungjo',
    'fangsong',
    'kaiti',
    'simkai',
    'mingliu',
    'pmingliu',
    'dfkai',
    'mhei',
    'msung',
    'fzlth',
    'fzss',
    'fzkt',
    'fzfs',
    'fzyh',
    'youyuan',
    'lisu',
    'batang',
    'gulim',
    'dotum',
    'malgun',
    'myungjo',
    'gungsuh',
    'hysmyeongjo',
    'hygothic',
    'nanum',
  ];

  static const List<String> _cjkSerifKeywords = [
    'mincho',
    'song',
    'ming',
    'kai',
    'fang',
    'ryumin',
    'batang',
    'myungjo',
    'gungsuh',
    'serif',
  ];

  static const List<String> _westernSansKeywords = [
    'arial',
    'helvetica',
    'roboto',
    'calibri',
    'verdana',
    'tahoma',
    'segoe',
    'trebuchet',
    'opensans',
    'lato',
    'dejavusans',
    'liberationsans',
  ];

  static const List<String> _westernSerifKeywords = [
    'times',
    'georgia',
    'garamond',
    'palatino',
    'cambria',
    'bookantiqua',
    'century',
    'dejavuserif',
    'liberationserif',
  ];

  static const List<String> _westernMonoKeywords = [
    'courier',
    'consolas',
    'menlo',
    'monaco',
    'lucidaconsole',
    'dejavusansmono',
    'liberationmono',
  ];

  final List<String> _searchDirectories;
  final Map<String, String?> _resolvedFileCache = {};

  String? findExistingFontFile(List<String> candidateFileNames) {
    for (final fileName in candidateFileNames) {
      if (_resolvedFileCache.containsKey(fileName)) {
        final cached = _resolvedFileCache[fileName];
        if (cached != null) return cached;
        continue;
      }
      String? found;
      for (final dir in _searchDirectories) {
        final candidatePath = p.join(dir, fileName);
        if (File(candidatePath).existsSync()) {
          found = candidatePath;
          break;
        }
      }
      _resolvedFileCache[fileName] = found;
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  String? get primaryCjkSansPath => findExistingFontFile(_cjkSansFiles);

  String? get primaryCjkSerifPath =>
      findExistingFontFile(_cjkSerifFiles) ?? primaryCjkSansPath;

  static String _normalizeAsciiFace(String rawFace) {
    final plusIdx = rawFace.indexOf('+');
    final withoutSubset = plusIdx >= 0 ? rawFace.substring(plusIdx + 1) : rawFace;
    return withoutSubset.replaceAll(RegExp('[^A-Za-z0-9]+'), '').toLowerCase();
  }

  static bool _hasUnicodeCjkSerifHint(String rawFace) {
    for (final unit in rawFace.codeUnits) {
      // Ming (U+660E), Song (U+5B8B), Kai (U+6977), Fang (U+4EFF)
      if (unit == 0x660E || unit == 0x5B8B || unit == 0x6977 || unit == 0x4EFF) {
        return true;
      }
    }
    return false;
  }

  bool _isCjkQuery(PdfFontQuery query, String normalizedFace) {
    switch (query.charset) {
      case PdfFontCharset.shiftJis:
      case PdfFontCharset.gb2312:
      case PdfFontCharset.chineseBig5:
      case PdfFontCharset.hangul:
        return true;
      default:
        break;
    }
    if (query.face.codeUnits.any((c) => c > 127)) {
      return true;
    }
    for (final kw in _cjkKeywords) {
      if (normalizedFace.contains(kw)) {
        return true;
      }
    }
    return false;
  }

  bool _prefersCjkSerif(PdfFontQuery query, String normalizedFace) {
    if (query.isRoman || _hasUnicodeCjkSerifHint(query.face)) {
      return true;
    }
    for (final kw in _cjkSerifKeywords) {
      if (normalizedFace.contains(kw)) {
        return true;
      }
    }
    return false;
  }

  String? _selectWesternStyledFile({
    required bool isBold,
    required bool isItalic,
    required String regular,
    required String bold,
    required String italic,
    required String boldItalic,
    List<String> fallbacks = const [],
  }) {
    final ordered = <String>[
      if (isBold && isItalic) boldItalic,
      if (isBold) bold,
      if (isItalic) italic,
      regular,
      ...fallbacks,
    ];
    return findExistingFontFile(ordered);
  }

  @override
  PdfFontResolution? resolve(PdfFontQuery query, PdfFontResolveContext context) {
    final normalized = _normalizeAsciiFace(query.face);
    final isBold = query.weight >= 600 || normalized.contains('bold');
    final isItalic =
        query.isItalic || normalized.contains('italic') || normalized.contains('oblique');

    // 1. Explicit CJK charset, non-ASCII localized font name, or known CJK family
    if (_isCjkQuery(query, normalized)) {
      final path = _prefersCjkSerif(query, normalized)
          ? primaryCjkSerifPath
          : (primaryCjkSansPath ?? primaryCjkSerifPath);
      if (path != null) {
        return PdfFontResolution.localFontFile(
          fontFilePath: path,
          targetFace: query.face,
        );
      }
    }

    // 2. Non-CJK international charsets
    switch (query.charset) {
      case PdfFontCharset.arabic:
        final arabicPath = findExistingFontFile(const [
              'NotoNaskhArabic-Bold.ttf',
              'NotoNaskhArabic-Regular.ttf',
              'NotoSansArabic-Regular.ttf',
            ]) ??
            primaryCjkSansPath;
        if (arabicPath != null) {
          return PdfFontResolution.localFontFile(
            fontFilePath: arabicPath,
            targetFace: query.face,
          );
        }
        break;
      case PdfFontCharset.hebrew:
        final hebrewPath = findExistingFontFile(const [
              'NotoSansHebrew-Bold.ttf',
              'NotoSansHebrew-Regular.ttf',
            ]) ??
            primaryCjkSansPath;
        if (hebrewPath != null) {
          return PdfFontResolution.localFontFile(
            fontFilePath: hebrewPath,
            targetFace: query.face,
          );
        }
        break;
      case PdfFontCharset.thai:
        final thaiPath = findExistingFontFile(const [
              'NotoSansThai-Bold.ttf',
              'NotoSansThai-Regular.ttf',
            ]) ??
            primaryCjkSansPath;
        if (thaiPath != null) {
          return PdfFontResolution.localFontFile(
            fontFilePath: thaiPath,
            targetFace: query.face,
          );
        }
        break;
      case PdfFontCharset.symbol:
        final symbolPath = findExistingFontFile(const [
              'NotoSansSymbols-Regular-Subsetted.ttf',
              'NotoSansSymbols-Regular-Subsetted2.ttf',
            ]) ??
            primaryCjkSansPath;
        if (symbolPath != null) {
          return PdfFontResolution.localFontFile(
            fontFilePath: symbolPath,
            targetFace: query.face,
          );
        }
        break;
      default:
        break;
    }

    // 3. Explicit Western monospace / serif / sans-serif font names
    if (_westernMonoKeywords.any(normalized.contains)) {
      final monoPath = findExistingFontFile(const [
        'DroidSansMono.ttf',
        'CutiveMono.ttf',
        'Roboto-Regular.ttf',
      ]);
      if (monoPath != null) {
        return PdfFontResolution.localFontFile(
          fontFilePath: monoPath,
          targetFace: query.face,
        );
      }
    }

    if (_westernSerifKeywords.any(normalized.contains)) {
      final serifPath = _selectWesternStyledFile(
        isBold: isBold,
        isItalic: isItalic,
        regular: 'NotoSerif-Regular.ttf',
        bold: 'NotoSerif-Bold.ttf',
        italic: 'NotoSerif-Italic.ttf',
        boldItalic: 'NotoSerif-BoldItalic.ttf',
        fallbacks: const ['DroidSerif-Regular.ttf', 'Roboto-Regular.ttf'],
      );
      if (serifPath != null) {
        return PdfFontResolution.localFontFile(
          fontFilePath: serifPath,
          targetFace: query.face,
        );
      }
    }

    if (_westernSansKeywords.any(normalized.contains)) {
      final sansPath = _selectWesternStyledFile(
        isBold: isBold,
        isItalic: isItalic,
        regular: 'Roboto-Regular.ttf',
        bold: 'Roboto-Bold.ttf',
        italic: 'Roboto-Italic.ttf',
        boldItalic: 'Roboto-BoldItalic.ttf',
        fallbacks: const ['DroidSans.ttf'],
      );
      if (sansPath != null) {
        return PdfFontResolution.localFontFile(
          fontFilePath: sansPath,
          targetFace: query.face,
        );
      }
    }

    // 4. Universal fallback for unrecognized/generic PDF font names (e.g. CIDFont+F1,
    // Identity-H unembedded fonts with default charset): prefer Pan-CJK Noto fonts
    // because they cover Latin, Cyrillic, Greek, AND full CJK glyphs simultaneously.
    final fallbackPath = (query.isRoman ? primaryCjkSerifPath : primaryCjkSansPath) ??
        _selectWesternStyledFile(
          isBold: isBold,
          isItalic: isItalic,
          regular: 'Roboto-Regular.ttf',
          bold: 'Roboto-Bold.ttf',
          italic: 'Roboto-Italic.ttf',
          boldItalic: 'Roboto-BoldItalic.ttf',
        );
    if (fallbackPath != null) {
      return PdfFontResolution.localFontFile(
        fontFilePath: fallbackPath,
        targetFace: query.face,
      );
    }
    return null;
  }
}

/// Manages Android system font registration for `pdfrx` so PDFs with
/// unembedded CJK or legacy CID fonts render accurately on Android devices.
class PdfSystemFontService {
  PdfSystemFontService._();

  static final PdfSystemFontService instance = PdfSystemFontService._();

  static const List<String> _preseededCjkSansFaces = [
    'HeiseiKakuGo-W5',
    'KozGoPro-Medium',
    'KozGoPr6N-Medium',
    'GothicBBB-Medium',
    'MS-Gothic',
    'MS-PGothic',
    'Meiryo',
    'SimHei',
    'MicrosoftYaHei',
    'AdobeHeitiStd-Regular',
    'MHei-Medium',
    'HYGoThic-Medium',
    'MalgunGothic',
    'Gulim',
  ];

  static const List<String> _preseededCjkSerifFaces = [
    'HeiseiMin-W3',
    'KozMinPro-Regular',
    'KozMinPr6N-Regular',
    'Ryumin-Light',
    'MS-Mincho',
    'MS-PMincho',
    'STSong-Light',
    'AdobeSongStd-Light',
    'SimSun',
    'NSimSun',
    'MSung-Light',
    'AdobeMingStd-Light',
    'MingLiU',
    'PMingLiU',
    'HYSMyeongJo-Medium',
    'Batang',
  ];

  late final AndroidSystemFontResolver _androidResolver =
      AndroidSystemFontResolver();
  PdfFontManager? _fontManager;
  bool _initialized = false;

  PdfFontManager get fontManager => _fontManager ??= _buildFontManager();

  PdfFontManager _buildFontManager() {
    if (Platform.isAndroid) {
      return PdfFontManager(resolvers: [_androidResolver]);
    }
    return PdfFontManager(resolvers: const []);
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (!Platform.isAndroid) return;

    await fontManager.prepare();

    final sansPath = _androidResolver.primaryCjkSansPath;
    final serifPath = _androidResolver.primaryCjkSerifPath;

    if (sansPath != null) {
      for (final face in _preseededCjkSansFaces) {
        await PdfrxEntryFunctions.instance.addFontFile(
          face: face,
          filePath: sansPath,
        );
      }
    }
    if (serifPath != null) {
      for (final face in _preseededCjkSerifFaces) {
        await PdfrxEntryFunctions.instance.addFontFile(
          face: face,
          filePath: serifPath,
        );
      }
    }
  }
}


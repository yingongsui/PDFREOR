import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Platform-specific candidate font files and directories for [SystemFontResolver].
class SystemFontProfile {
  final List<String> searchDirectories;
  final List<String> cjkSansFiles;
  final List<String> cjkSerifFiles;
  final List<String> arabicFiles;
  final List<String> hebrewFiles;
  final List<String> thaiFiles;
  final List<String> symbolFiles;
  final List<String> westernMonoFiles;
  final String westernSerifRegular;
  final String westernSerifBold;
  final String westernSerifItalic;
  final String westernSerifBoldItalic;
  final List<String> westernSerifFallbacks;
  final String westernSansRegular;
  final String westernSansBold;
  final String westernSansItalic;
  final String westernSansBoldItalic;
  final List<String> westernSansFallbacks;

  const SystemFontProfile({
    required this.searchDirectories,
    required this.cjkSansFiles,
    required this.cjkSerifFiles,
    required this.arabicFiles,
    required this.hebrewFiles,
    required this.thaiFiles,
    required this.symbolFiles,
    required this.westernMonoFiles,
    required this.westernSerifRegular,
    required this.westernSerifBold,
    required this.westernSerifItalic,
    required this.westernSerifBoldItalic,
    this.westernSerifFallbacks = const [],
    required this.westernSansRegular,
    required this.westernSansBold,
    required this.westernSansItalic,
    required this.westernSansBoldItalic,
    this.westernSansFallbacks = const [],
  });
}

/// Resolves missing PDF fonts (especially non-embedded CJK CID/legacy-encoded fonts
/// and international scripts) to built-in OS system font files without copying
/// multi-megabyte TTC/TTF collections into app storage.
class SystemFontResolver implements PdfFontResolver {
  SystemFontResolver({
    required this.profile,
    List<String>? searchDirectories,
  }) : _searchDirectories = searchDirectories ?? profile.searchDirectories;

  final SystemFontProfile profile;

  static const SystemFontProfile macOsProfile = SystemFontProfile(
    searchDirectories: [
      '/System/Library/Fonts',
      '/System/Library/Fonts/Supplemental',
      '/Library/Fonts',
    ],
    cjkSansFiles: [
      'Hiragino Sans GB.ttc',
      'STHeiti Medium.ttc',
      'STHeiti Light.ttc',
      'ヒラギノ角ゴシック W3.ttc',
      'AppleSDGothicNeo.ttc',
      'Arial Unicode.ttf',
    ],
    cjkSerifFiles: [
      'Songti.ttc',
      'ヒラギノ明朝 ProN.ttc',
    ],
    arabicFiles: [
      'GeezaPro.ttc',
      'SFArabic.ttf',
    ],
    hebrewFiles: [
      'ArialHB.ttc',
      'SFHebrew.ttf',
    ],
    thaiFiles: [
      'Thonburi.ttc',
      'ThonburiUI.ttc',
    ],
    symbolFiles: [
      'Apple Symbols.ttf',
      'Symbol.ttf',
    ],
    westernMonoFiles: [
      'Menlo.ttc',
      'Courier.ttc',
      'Courier New.ttf',
      'Monaco.ttf',
    ],
    westernSerifRegular: 'Times New Roman.ttf',
    westernSerifBold: 'Times New Roman Bold.ttf',
    westernSerifItalic: 'Times New Roman Italic.ttf',
    westernSerifBoldItalic: 'Times New Roman Bold Italic.ttf',
    westernSerifFallbacks: ['Times.ttc', 'Georgia.ttf'],
    westernSansRegular: 'Arial.ttf',
    westernSansBold: 'Arial Bold.ttf',
    westernSansItalic: 'Arial Italic.ttf',
    westernSansBoldItalic: 'Arial Bold Italic.ttf',
    westernSansFallbacks: ['Helvetica.ttc', 'HelveticaNeue.ttc'],
  );

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

  String? get primaryCjkSansPath => findExistingFontFile(profile.cjkSansFiles);

  String? get primaryCjkSerifPath =>
      findExistingFontFile(profile.cjkSerifFiles) ?? primaryCjkSansPath;

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
    if (normalizedFace.contains('serif') && !normalizedFace.contains('sans')) {
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
        final arabicPath = findExistingFontFile(profile.arabicFiles) ?? primaryCjkSansPath;
        if (arabicPath != null) {
          return PdfFontResolution.localFontFile(
            fontFilePath: arabicPath,
            targetFace: query.face,
          );
        }
        break;
      case PdfFontCharset.hebrew:
        final hebrewPath = findExistingFontFile(profile.hebrewFiles) ?? primaryCjkSansPath;
        if (hebrewPath != null) {
          return PdfFontResolution.localFontFile(
            fontFilePath: hebrewPath,
            targetFace: query.face,
          );
        }
        break;
      case PdfFontCharset.thai:
        final thaiPath = findExistingFontFile(profile.thaiFiles) ?? primaryCjkSansPath;
        if (thaiPath != null) {
          return PdfFontResolution.localFontFile(
            fontFilePath: thaiPath,
            targetFace: query.face,
          );
        }
        break;
      case PdfFontCharset.symbol:
        final symbolPath = findExistingFontFile(profile.symbolFiles) ?? primaryCjkSansPath;
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
      final monoPath = findExistingFontFile(profile.westernMonoFiles);
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
        regular: profile.westernSerifRegular,
        bold: profile.westernSerifBold,
        italic: profile.westernSerifItalic,
        boldItalic: profile.westernSerifBoldItalic,
        fallbacks: profile.westernSerifFallbacks,
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
        regular: profile.westernSansRegular,
        bold: profile.westernSansBold,
        italic: profile.westernSansItalic,
        boldItalic: profile.westernSansBoldItalic,
        fallbacks: profile.westernSansFallbacks,
      );
      if (sansPath != null) {
        return PdfFontResolution.localFontFile(
          fontFilePath: sansPath,
          targetFace: query.face,
        );
      }
    }

    // 4. Universal fallback for unrecognized/generic PDF font names (e.g. CIDFont+F1,
    // Identity-H unembedded fonts with default charset): prefer Pan-CJK fonts
    // because they cover Latin, Cyrillic, Greek, AND full CJK glyphs simultaneously.
    final fallbackPath = (query.isRoman ? primaryCjkSerifPath : primaryCjkSansPath) ??
        _selectWesternStyledFile(
          isBold: isBold,
          isItalic: isItalic,
          regular: profile.westernSansRegular,
          bold: profile.westernSansBold,
          italic: profile.westernSansItalic,
          boldItalic: profile.westernSansBoldItalic,
          fallbacks: profile.westernSansFallbacks,
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

/// macOS built-in system font resolver.
class MacOsSystemFontResolver extends SystemFontResolver {
  MacOsSystemFontResolver({super.searchDirectories})
      : super(profile: SystemFontResolver.macOsProfile);
}

/// Manages system font registration for `pdfrx` so PDFs with
/// unembedded CJK or legacy CID fonts render accurately on desktop devices.
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

  late final SystemFontResolver? _platformResolver = _createPlatformResolver();
  PdfFontManager? _fontManager;
  Future<void>? _initFuture;

  SystemFontResolver? _createPlatformResolver() {
    if (Platform.isMacOS) {
      return MacOsSystemFontResolver();
    }
    return null;
  }

  PdfFontManager get fontManager => _fontManager ??= _buildFontManager();

  PdfFontManager _buildFontManager() {
    final resolver = _platformResolver;
    if (resolver != null) {
      return PdfFontManager(resolvers: [resolver]);
    }
    return PdfFontManager(resolvers: const []);
  }

  Future<void> init() {
    return _initFuture ??= _initInternal();
  }

  Future<void> _initInternal() async {
    final resolver = _platformResolver;
    if (resolver == null) return;

    await fontManager.prepare();

    final sansPath = resolver.primaryCjkSansPath;
    final serifPath = resolver.primaryCjkSerifPath;

    final registrations = <Future<void>>[
      if (sansPath != null)
        for (final face in _preseededCjkSansFaces)
          PdfrxEntryFunctions.instance.addFontFile(
            face: face,
            filePath: sansPath,
          ),
      if (serifPath != null)
        for (final face in _preseededCjkSerifFaces)
          PdfrxEntryFunctions.instance.addFontFile(
            face: face,
            filePath: serifPath,
          ),
    ];
    if (registrations.isNotEmpty) {
      await Future.wait(registrations);
    }
  }
}


import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/editor_models.dart';
import 'app_data_directory.dart';
import 'atomic_file_store.dart';

enum AnnotationPersistenceMode {
  fileDefault,     // Follow file: editable if embedded Advanced payload exists, else standard flattened
  alwaysEditable,  // Always embed Advanced independent annotation streams + JSON attachment
  alwaysFlattened, // Always flatten to standard PDF (strip any prior Advanced payload on save)
}

enum AppFontFamily {
  sansSerif, // Sans-Serif (Modern / HeiTi / Noto Sans / Helvetica)
  serif,     // Serif (Classical / SongTi / Mincho / Times Roman)
  monospace; // Monospace (Code / Courier)

  String get fontFamily {
    switch (this) {
      case AppFontFamily.serif:
        if (Platform.isLinux) return 'Liberation Serif';
        return 'Times New Roman';
      case AppFontFamily.monospace:
        if (Platform.isMacOS) return 'Menlo';
        if (Platform.isWindows) return 'Consolas';
        if (Platform.isLinux) return 'DejaVu Sans Mono';
        return 'Courier New';
      case AppFontFamily.sansSerif:
        if (Platform.isMacOS) return 'Helvetica Neue';
        if (Platform.isWindows) return 'Segoe UI';
        if (Platform.isLinux) return 'Noto Sans';
        return 'Arial';
    }
  }

  List<String> get fontFamilyFallback {
    switch (this) {
      case AppFontFamily.serif:
        return const [
          'Times New Roman',
          'Georgia',
          'Times',
          'Liberation Serif',
          'DejaVu Serif',
          'Noto Serif',
          'Songti SC',
          'Hiragino Mincho ProN',
          'SimSun',
          'Noto Serif CJK SC',
        ];
      case AppFontFamily.monospace:
        return const [
          'Menlo',
          'Consolas',
          'Courier New',
          'Courier',
          'Liberation Mono',
          'DejaVu Sans Mono',
          'Noto Sans Mono',
        ];
      case AppFontFamily.sansSerif:
        return const [
          'Helvetica Neue',
          'Segoe UI',
          'Arial',
          'Noto Sans',
          'Liberation Sans',
          'DejaVu Sans',
          'PingFang SC',
          'Hiragino Sans',
          'Apple SD Gothic Neo',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
        ];
    }
  }
}

const List<String> kDefaultLatexOperators = [
  r'\frac{a}{b}',
  r'\sqrt{x}',
  r'^{2}',
  r'_{i}',
  r'\pm',
  r'\times',
  r'\div',
  r'\neq',
  r'\leq',
  r'\geq',
  r'\approx',
  r'\infty',
  r'\pi',
  r'\alpha',
  r'\beta',
  r'\theta',
  r'\sum_{i=1}^{n}',
  r'\int_{a}^{b}',
  r'\partial',
  r'\Delta',
];

class EditorSettings {
  final Color activeColor;
  final Color highlightColor;
  final Color underlineColor;
  final double activeStrokeWidth;
  final ShapeType activeShape;
  final double toolbarPositionX;
  final double toolbarPositionY;
  final bool toolbarCollapsed;
  final AppFontFamily textBoxFont;
  final List<String> latexQuickOperators;
  final AnnotationPersistenceMode annotationPersistenceMode;

  const EditorSettings({
    this.activeColor = const Color(0xFF212121),
    this.highlightColor = const Color(0xFFFFEB3B),
    this.underlineColor = const Color(0xFFF44336),
    this.activeStrokeWidth = 3.0,
    this.activeShape = ShapeType.rectangle,
    this.toolbarPositionX = 12.0,
    this.toolbarPositionY = 100.0,
    this.toolbarCollapsed = false,
    this.textBoxFont = AppFontFamily.sansSerif,
    this.latexQuickOperators = kDefaultLatexOperators,
    this.annotationPersistenceMode = AnnotationPersistenceMode.fileDefault,
  });

  EditorSettings copyWith({
    Color? activeColor,
    Color? highlightColor,
    Color? underlineColor,
    double? activeStrokeWidth,
    ShapeType? activeShape,
    double? toolbarPositionX,
    double? toolbarPositionY,
    bool? toolbarCollapsed,
    AppFontFamily? textBoxFont,
    List<String>? latexQuickOperators,
    AnnotationPersistenceMode? annotationPersistenceMode,
  }) {
    return EditorSettings(
      activeColor: activeColor ?? this.activeColor,
      highlightColor: highlightColor ?? this.highlightColor,
      underlineColor: underlineColor ?? this.underlineColor,
      activeStrokeWidth: activeStrokeWidth ?? this.activeStrokeWidth,
      activeShape: activeShape ?? this.activeShape,
      toolbarPositionX: toolbarPositionX ?? this.toolbarPositionX,
      toolbarPositionY: toolbarPositionY ?? this.toolbarPositionY,
      toolbarCollapsed: toolbarCollapsed ?? this.toolbarCollapsed,
      textBoxFont: textBoxFont ?? this.textBoxFont,
      latexQuickOperators: latexQuickOperators ?? this.latexQuickOperators,
      annotationPersistenceMode:
          annotationPersistenceMode ?? this.annotationPersistenceMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'activeColor': activeColor.toARGB32(),
        'highlightColor': highlightColor.toARGB32(),
        'underlineColor': underlineColor.toARGB32(),
        'activeStrokeWidth': activeStrokeWidth,
        'activeShape': activeShape.index,
        'toolbarPositionX': toolbarPositionX,
        'toolbarPositionY': toolbarPositionY,
        'toolbarCollapsed': toolbarCollapsed,
        'textBoxFont': textBoxFont.index,
        'latexQuickOperators': latexQuickOperators,
        'annotationPersistenceMode': annotationPersistenceMode.index,
      };

  factory EditorSettings.fromJson(Map<String, dynamic> json) {
    final shapeIdx = (json['activeShape'] as num?)?.toInt();
    final fontIdx = (json['textBoxFont'] as num?)?.toInt();
    final persistenceIdx = (json['annotationPersistenceMode'] as num?)?.toInt();
    return EditorSettings(
      activeColor: json['activeColor'] != null
          ? Color(json['activeColor'] as int)
          : const Color(0xFF212121),
      highlightColor: json['highlightColor'] != null
          ? Color(json['highlightColor'] as int)
          : const Color(0xFFFFEB3B),
      underlineColor: json['underlineColor'] != null
          ? Color(json['underlineColor'] as int)
          : const Color(0xFFF44336),
      activeStrokeWidth: (json['activeStrokeWidth'] as num?)?.toDouble() ?? 3.0,
      activeShape: shapeIdx != null &&
              shapeIdx >= 0 &&
              shapeIdx < ShapeType.values.length
          ? ShapeType.values[shapeIdx]
          : ShapeType.rectangle,
      toolbarPositionX: (json['toolbarPositionX'] as num?)?.toDouble() ?? 12.0,
      toolbarPositionY: (json['toolbarPositionY'] as num?)?.toDouble() ?? 100.0,
      toolbarCollapsed: (json['toolbarCollapsed'] as bool?) ?? false,
      textBoxFont: fontIdx != null &&
              fontIdx >= 0 &&
              fontIdx < AppFontFamily.values.length
          ? AppFontFamily.values[fontIdx]
          : AppFontFamily.sansSerif,
      latexQuickOperators: json['latexQuickOperators'] != null
          ? List<String>.from(json['latexQuickOperators'] as List)
          : kDefaultLatexOperators,
      annotationPersistenceMode: persistenceIdx != null &&
              persistenceIdx >= 0 &&
              persistenceIdx < AnnotationPersistenceMode.values.length
          ? AnnotationPersistenceMode.values[persistenceIdx]
          : AnnotationPersistenceMode.fileDefault,
    );
  }
}

class EditorSettingsService {
  static const _fileName = 'editor_settings.json';
  static EditorSettings? _cachedSettings;
  static Future<EditorSettings>? _loadFuture;
  static int _mutationEpoch = 0;
  static final ValueNotifier<EditorSettings> settingsNotifier =
      ValueNotifier<EditorSettings>(const EditorSettings());

  static Future<File> _getFile() {
    return AppDataDirectory.resolveFile(_fileName);
  }

  static Future<EditorSettings> loadSettings() async {
    if (_cachedSettings != null) return _cachedSettings!;
    return _loadFuture ??= _loadSettingsFromDisk();
  }

  static Future<EditorSettings> _loadSettingsFromDisk() async {
    final epochAtStart = _mutationEpoch;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        if (_mutationEpoch != epochAtStart && _cachedSettings != null) {
          return _cachedSettings!;
        }
        _cachedSettings = EditorSettings.fromJson(map);
        settingsNotifier.value = _cachedSettings!;
        return _cachedSettings!;
      }
    } catch (e) {
      debugPrint('Error loading editor settings: $e');
    } finally {
      _loadFuture = null;
    }
    if (_mutationEpoch != epochAtStart && _cachedSettings != null) {
      return _cachedSettings!;
    }
    _cachedSettings = const EditorSettings();
    settingsNotifier.value = _cachedSettings!;
    return _cachedSettings!;
  }

  static Future<void> saveSettings(EditorSettings settings) async {
    _mutationEpoch++;
    _cachedSettings = settings;
    settingsNotifier.value = settings;
    try {
      final file = await _getFile();
      await AtomicFileStore.writeString(file, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('Error saving editor settings: $e');
    }
  }
}


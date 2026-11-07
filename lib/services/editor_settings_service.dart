import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/editor_models.dart';
import 'pdf_export_service.dart';

enum AppFontFamily {
  sansSerif, // Sans-Serif (Modern / HeiTi / Noto Sans / Helvetica)
  serif,     // Serif (Classical / SongTi / Mincho / Times Roman)
  monospace; // Monospace (Code / Courier)

  String get cssFontFamily {
    switch (this) {
      case AppFontFamily.serif:
        return 'serif';
      case AppFontFamily.monospace:
        return 'monospace';
      case AppFontFamily.sansSerif:
        return 'sans-serif';
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
      };

  factory EditorSettings.fromJson(Map<String, dynamic> json) {
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
      activeShape: json['activeShape'] != null &&
              (json['activeShape'] as int) < ShapeType.values.length
          ? ShapeType.values[json['activeShape'] as int]
          : ShapeType.rectangle,
      toolbarPositionX: (json['toolbarPositionX'] as num?)?.toDouble() ?? 12.0,
      toolbarPositionY: (json['toolbarPositionY'] as num?)?.toDouble() ?? 100.0,
      toolbarCollapsed: (json['toolbarCollapsed'] as bool?) ?? false,
      textBoxFont: json['textBoxFont'] != null &&
              (json['textBoxFont'] as int) < AppFontFamily.values.length
          ? AppFontFamily.values[json['textBoxFont'] as int]
          : AppFontFamily.sansSerif,
      latexQuickOperators: json['latexQuickOperators'] != null
          ? List<String>.from(json['latexQuickOperators'] as List)
          : kDefaultLatexOperators,
    );
  }
}

class EditorSettingsService {
  static const _fileName = 'editor_settings.json';
  static EditorSettings? _cachedSettings;
  static final ValueNotifier<EditorSettings> settingsNotifier =
      ValueNotifier<EditorSettings>(const EditorSettings());

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<EditorSettings> loadSettings() async {
    if (_cachedSettings != null) return _cachedSettings!;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        _cachedSettings = EditorSettings.fromJson(map);
        settingsNotifier.value = _cachedSettings!;
        return _cachedSettings!;
      }
    } catch (e) {
      debugPrint('Error loading editor settings: $e');
    }
    _cachedSettings = const EditorSettings();
    settingsNotifier.value = _cachedSettings!;
    return _cachedSettings!;
  }

  static Future<void> saveSettings(EditorSettings settings) async {
    _cachedSettings = settings;
    settingsNotifier.value = settings;
    try {
      final file = await _getFile();
      await PdfExportService.atomicWriteString(file, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('Error saving editor settings: $e');
    }
  }
}


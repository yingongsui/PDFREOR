import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'screens/home_screen.dart';
import 'services/editor_settings_service.dart';
import 'services/pdf_system_font_service.dart';
import 'services/pdf_tab_manager.dart';
import 'services/reading_progress_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await Future.wait([
    pdfrxFlutterInitialize()
        .then((_) => PdfSystemFontService.instance.init())
        .catchError((e) => debugPrint('Font service init warning: $e')),
    PdfTabManager.instance
        .init()
        .catchError((e) => debugPrint('Tab manager init warning: $e')),
    ReadingProgressService.instance
        .init()
        .catchError((e) => debugPrint('Reading progress init warning: $e')),
    EditorSettingsService.loadSettings()
        .then<void>((_) {})
        .catchError((e) => debugPrint('Settings init warning: $e')),
  ]);
  runApp(const PDFREORApp());
}

class PDFREORApp extends StatelessWidget {
  const PDFREORApp({super.key});

  static ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E88E5),
      brightness: brightness,
    );
    final overlayBrightness =
        brightness == Brightness.dark ? Brightness.light : Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: overlayBrightness,
          systemNavigationBarIconBrightness: overlayBrightness,
        ),
      ),
      cardTheme: const CardThemeData(
        clipBehavior: Clip.antiAlias,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDFREOR',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

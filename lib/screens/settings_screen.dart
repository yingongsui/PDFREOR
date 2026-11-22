import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/editor_settings_service.dart';
import '../services/pdf_scanner_service.dart';
import '../services/platform_bridge.dart';
import 'home/home_dialogs.dart';
import 'settings/latex_operators_section.dart';
import 'settings/settings_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  EditorSettings _editorSettings = const EditorSettings();
  Set<String> _hiddenFolders = {};

  @override
  void initState() {
    super.initState();
    EditorSettingsService.loadSettings().then((s) {
      if (mounted) setState(() => _editorSettings = s);
    });
    _loadHiddenFolders();
  }

  Future<void> _loadHiddenFolders() async {
    final hidden = await PdfScannerService.instance.getHiddenFolders();
    if (mounted) {
      setState(() => _hiddenFolders = hidden);
    }
  }

  Future<void> _updateEditorSettings(EditorSettings updated) async {
    if (mounted) {
      setState(() => _editorSettings = updated);
    }
    await EditorSettingsService.saveSettings(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Section: Editor & Text Box Font
          const SettingsSectionHeader(title: 'Editor & Annotation', icon: Icons.edit_note_rounded),
          const SizedBox(height: 8),
          SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsCardHeader(
                  icon: Icons.font_download_outlined,
                  title: 'Text Box Font Style',
                  subtitle: 'Font family used during input typing and in the saved PDF',
                ),
                const SizedBox(height: 14),
                  SegmentedButton<AppFontFamily>(
                    segments: const [
                      ButtonSegment<AppFontFamily>(
                        value: AppFontFamily.sansSerif,
                        label: Text('Sans-Serif'),
                        icon: Icon(Icons.format_size_rounded, size: 16),
                      ),
                      ButtonSegment<AppFontFamily>(
                        value: AppFontFamily.serif,
                        label: Text('Serif'),
                        icon: Icon(Icons.font_download_rounded, size: 16),
                      ),
                      ButtonSegment<AppFontFamily>(
                        value: AppFontFamily.monospace,
                        label: Text('Mono'),
                        icon: Icon(Icons.code_rounded, size: 16),
                      ),
                    ],
                    selected: {_editorSettings.textBoxFont},
                    onSelectionChanged: (newSelection) async {
                      final updated = _editorSettings.copyWith(textBoxFont: newSelection.first);
                      setState(() {
                        _editorSettings = updated;
                      });
                      await EditorSettingsService.saveSettings(updated);
                    },
                  ),
                  const SizedBox(height: 12),
                  // Font Live Preview
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live Font Preview:',
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'One more time, 1 more chance.',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: _editorSettings.textBoxFont.fontFamily,
                            fontFamilyFallback: _editorSettings.textBoxFont.fontFamilyFallback,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ),

          const SizedBox(height: 12),

          // Math Formula Quick Operators Card
          LatexOperatorsCard(
            editorSettings: _editorSettings,
            onSettingsUpdated: _updateEditorSettings,
          ),

          const SizedBox(height: 12),

          // Annotation Persistence Mode Card
          SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsCardHeader(
                  icon: Icons.layers_rounded,
                  title: 'Annotation Persistence Mode',
                  subtitle: 'Default format on open and tap-Save (hold Save for options)',
                  titleFontSize: 15,
                ),
                const SizedBox(height: 12),
                  for (final option in const [
                    (
                      mode: AnnotationPersistenceMode.fileDefault,
                      title: 'Auto (Follow File)',
                      subtitle: 'Reopen Advanced files as editable; keep plain PDFs as Standard.',
                    ),
                    (
                      mode: AnnotationPersistenceMode.alwaysEditable,
                      title: 'Always Advanced (Editable)',
                      subtitle: 'Embed tagged annotation stream + JSON so edits stay editable after reopen.',
                    ),
                    (
                      mode: AnnotationPersistenceMode.alwaysFlattened,
                      title: 'Always Standard (Flattened)',
                      subtitle: 'Bake annotations as plain PDF graphics with no embedded JSON.',
                    ),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          _updateEditorSettings(
                            _editorSettings.copyWith(
                              annotationPersistenceMode: option.mode,
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _editorSettings.annotationPersistenceMode == option.mode
                                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
                                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _editorSettings.annotationPersistenceMode == option.mode
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _editorSettings.annotationPersistenceMode == option.mode
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 20,
                                color: _editorSettings.annotationPersistenceMode == option.mode
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      option.title,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      option.subtitle,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: theme.colorScheme.onSurfaceVariant,
                                        height: 1.25,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ),

          const SizedBox(height: 24),

          // Section: Storage & Cache
          const SettingsSectionHeader(title: 'Storage & Maintenance', icon: Icons.storage_rounded),
          const SizedBox(height: 8),
          SettingsCard(
            padding: null,
            child: Column(
              children: [
                ListTile(
                  leading: const SettingsIconBadge(icon: Icons.cleaning_services_rounded),
                  title: const Text('Clear Thumbnail Cache', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Free memory and reload document previews'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showClearThumbnailCacheDialog(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const SettingsIconBadge(icon: Icons.visibility_off_outlined),
                  title: const Text('Hidden Folders', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _hiddenFolders.isEmpty
                        ? 'No folders hidden from the home screen'
                        : '${_hiddenFolders.length} ${_hiddenFolders.length == 1 ? 'folder' : 'folders'} hidden • Tap to restore',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await showHiddenFoldersDialog(
                      context,
                      hiddenFolders: _hiddenFolders,
                      onUnhideFolder: (folderPath) async {
                        await PdfScannerService.instance.setFolderHidden(folderPath, false);
                        await _loadHiddenFolders();
                      },
                      onUnhideAll: () async {
                        await PdfScannerService.instance.clearHiddenFolders();
                        await _loadHiddenFolders();
                      },
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section: About
          const SettingsSectionHeader(title: 'About', icon: Icons.info_outline_rounded),
          const SizedBox(height: 8),
          SettingsCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/app_icon.png',
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PDFREOR',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Version 1.3.0',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'A fast, responsive PDF reader and annotation editor.',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Material(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _openGitHubUrl(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.code_rounded,
                              color: theme.colorScheme.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'GitHub Repository',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'https://github.com/yingongsui/PDFREOR',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              tooltip: 'Copy link',
                              onPressed: () => _copyGitHubLink(context),
                            ),
                            const Icon(Icons.open_in_new_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  const SettingsFeatureRow(icon: Icons.tab_rounded, text: 'Multi-tab document management'),
                  const SettingsFeatureRow(icon: Icons.draw_rounded, text: 'Stylus palm rejection & hardware button eraser'),
                  const SettingsFeatureRow(icon: Icons.category_rounded, text: 'Vector shapes, text boxes & ink drawing'),
                  const SettingsFeatureRow(icon: Icons.folder_rounded, text: 'Folder grouping & library organization'),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Platform.isMacOS ? Icons.desktop_mac_rounded : Icons.computer_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Desktop',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SettingsFeatureRow(
                    icon: Icons.mouse_rounded,
                    text:
                        'Mouse text selection, right-click context menus & ${Platform.isMacOS ? 'Cmd' : 'Ctrl'} + Scroll zoom',
                  ),
                  const SettingsFeatureRow(
                    icon: Icons.keyboard_rounded,
                    text: 'Keyboard shortcuts (Save, Close Tab, Undo, Copy & Delete selected)',
                  ),
                  const SettingsFeatureRow(
                    icon: Icons.content_paste_rounded,
                    text: 'Clipboard image & text paste with resize and quick delete',
                  ),
                ],
              ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }


  static const String _githubUrl = 'https://github.com/yingongsui/PDFREOR';

  Future<void> _copyGitHubLink(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _githubUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('GitHub link copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openGitHubUrl(BuildContext context) async {
    final success = await PlatformBridge.openUrl(_githubUrl);
    if (!success && context.mounted) {
      await _copyGitHubLink(context);
    }
  }
}


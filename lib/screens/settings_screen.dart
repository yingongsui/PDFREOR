import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../services/editor_settings_service.dart';
import '../services/pdf_scanner_service.dart';
import '../services/pdf_thumbnail_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final PdfScannerService _scannerService = PdfScannerService.instance;
  bool _hasPermission = false;
  bool _isChecking = true;
  EditorSettings _editorSettings = const EditorSettings();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
    EditorSettingsService.loadSettings().then((s) {
      if (mounted) setState(() => _editorSettings = s);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    final granted = await _scannerService.hasStoragePermission();
    if (mounted) {
      setState(() {
        _hasPermission = granted;
        _isChecking = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    final granted = await _scannerService.requestStoragePermission();
    if (mounted) {
      setState(() {
        _hasPermission = granted;
      });
      if (!granted) {
        _scannerService.openSettings();
      }
    }
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Clear Thumbnail Cache'),
          ],
        ),
        content: const Text(
          'This will clear cached PDF thumbnails. Thumbnails will be regenerated automatically as you browse files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await PdfThumbnailService.instance.clearAllCache();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Thumbnail cache cleared successfully'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
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
          // Section: Permissions
          _buildSectionHeader(theme, 'Permissions', Icons.security_rounded),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _hasPermission
                              ? Colors.green.withValues(alpha: 0.12)
                              : Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _hasPermission ? Icons.check_circle_rounded : Icons.warning_rounded,
                          color: _hasPermission ? Colors.green : Colors.orange,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'All-Files Storage Access',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isChecking
                                  ? 'Checking permission status...'
                                  : _hasPermission
                                      ? 'Granted • Device storage scanning enabled'
                                      : 'Not granted • Required to scan and read PDFs',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _hasPermission
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _hasPermission ? 'GRANTED' : 'REQUIRED',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _hasPermission ? Colors.green.shade800 : Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!_hasPermission)
                        FilledButton.tonalIcon(
                          onPressed: _requestPermission,
                          icon: const Icon(Icons.lock_open_rounded, size: 16),
                          label: const Text('Grant Access'),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () => _scannerService.openSettings(),
                          icon: const Icon(Icons.settings_rounded, size: 16),
                          label: const Text('Manage in Settings'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Section: Editor & Text Box Font
          _buildSectionHeader(theme, 'Editor & Annotation', Icons.edit_note_rounded),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.font_download_outlined, color: theme.colorScheme.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Text Box Font Style',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Font family used during input typing and in the saved PDF',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                          'The quick brown fox jumps over the lazy dog. 12345',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: _editorSettings.textBoxFont.cssFontFamily,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Math Formula Quick Operators Card
          _buildMathFormulaOperatorsCard(theme),

          const SizedBox(height: 24),

          // Section: Storage & Cache
          _buildSectionHeader(theme, 'Storage & Maintenance', Icons.storage_rounded),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.cleaning_services_rounded, color: theme.colorScheme.primary, size: 22),
              ),
              title: const Text('Clear Thumbnail Cache', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Free memory and reload document previews'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _showClearCacheDialog,
            ),
          ),

          const SizedBox(height: 24),

          // Section: About
          _buildSectionHeader(theme, 'About', Icons.info_outline_rounded),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
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
                            'Version 2.3.0',
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
                    'A fast, responsive PDF reader and annotation editor tailored for Android tablets and active styluses.',
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
                              onPressed: () {
                                Clipboard.setData(
                                  const ClipboardData(text: 'https://github.com/yingongsui/PDFREOR'),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('GitHub link copied to clipboard'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
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
                  _buildFeatureRow(Icons.tab_rounded, 'Multi-tab document management'),
                  _buildFeatureRow(Icons.draw_rounded, 'Stylus palm rejection & hardware button eraser'),
                  _buildFeatureRow(Icons.category_rounded, 'Vector shapes, text boxes & ink drawing'),
                  _buildFeatureRow(Icons.folder_rounded, 'Folder grouping & library organization'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddOperatorDialog() async {
    final added = await showDialog<String>(
      context: context,
      builder: (_) => const _AddOperatorDialog(),
    );
    if (added == null || added.isEmpty || !mounted) return;
    final current = List<String>.from(_editorSettings.latexQuickOperators);
    if (!current.contains(added)) {
      current.add(added);
      final updated = _editorSettings.copyWith(latexQuickOperators: current);
      setState(() => _editorSettings = updated);
      await EditorSettingsService.saveSettings(updated);
    }
  }

  Future<void> _showReorderOperatorsSheet() async {
    final theme = Theme.of(context);
    final reorderedList = List<String>.from(_editorSettings.latexQuickOperators);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(Icons.swap_vert_rounded, color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          const Text(
                            'Reorder Operators',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          FilledButton.tonal(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Drag the handle on the right to reorder formula shortcuts',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: ReorderableListView.builder(
                        itemCount: reorderedList.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setSheetState(() {
                            final item = reorderedList.removeAt(oldIndex);
                            reorderedList.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final op = reorderedList[index];
                          return ListTile(
                            key: ValueKey('op_reorder_${op}_$index'),
                            leading: Container(
                              width: 52,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                              child: Math.tex(
                                op,
                                textStyle: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface,
                                ),
                                mathStyle: MathStyle.display,
                                onErrorFallback: (_) => Text(op, style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                            title: Text(
                              op,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Icon(Icons.drag_handle_rounded, color: Colors.grey),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    final updated = _editorSettings.copyWith(latexQuickOperators: reorderedList);
    setState(() => _editorSettings = updated);
    await EditorSettingsService.saveSettings(updated);
  }

  Widget _buildMathFormulaOperatorsCard(ThemeData theme) {
    final operators = _editorSettings.latexQuickOperators;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.functions_rounded, color: theme.colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Math Formula Operators',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Quick shortcuts available when editing formulas • Drag to reorder',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < operators.length; i++)
                  DragTarget<int>(
                    onWillAcceptWithDetails: (details) => details.data != i,
                    onAcceptWithDetails: (details) async {
                      final oldIndex = details.data;
                      final newIndex = i;
                      final updatedList = List<String>.from(operators);
                      final item = updatedList.removeAt(oldIndex);
                      updatedList.insert(newIndex, item);
                      final updated = _editorSettings.copyWith(latexQuickOperators: updatedList);
                      setState(() => _editorSettings = updated);
                      await EditorSettingsService.saveSettings(updated);
                    },
                    builder: (context, candidateData, rejectedData) {
                      final isTargeted = candidateData.isNotEmpty;
                      final chipWidget = InputChip(
                        avatar: Icon(
                          Icons.drag_indicator_rounded,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        label: Math.tex(
                          operators[i],
                          textStyle: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface,
                          ),
                          mathStyle: MathStyle.display,
                          onErrorFallback: (_) => Text(
                            operators[i],
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        deleteIcon: const Icon(Icons.close_rounded, size: 14),
                        onDeleted: () async {
                          final updatedList = List<String>.from(operators)..removeAt(i);
                          final updated = _editorSettings.copyWith(latexQuickOperators: updatedList);
                          setState(() => _editorSettings = updated);
                          await EditorSettingsService.saveSettings(updated);
                        },
                      );

                      return LongPressDraggable<int>(
                        data: i,
                        delay: const Duration(milliseconds: 180),
                        hapticFeedbackOnStart: true,
                        feedback: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: theme.colorScheme.primary, width: 1.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
                              ],
                            ),
                            child: Math.tex(
                              operators[i],
                              textStyle: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                              mathStyle: MathStyle.display,
                              onErrorFallback: (_) => Text(operators[i]),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(opacity: 0.25, child: chipWidget),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: isTargeted
                                ? Border.all(color: theme.colorScheme.primary, width: 2)
                                : null,
                            color: isTargeted
                                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                                : Colors.transparent,
                          ),
                          child: chipWidget,
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _showAddOperatorDialog,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Operator'),
                ),
                OutlinedButton.icon(
                  onPressed: _showReorderOperatorsSheet,
                  icon: const Icon(Icons.swap_vert_rounded, size: 16),
                  label: const Text('Reorder List'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final updated = _editorSettings.copyWith(latexQuickOperators: kDefaultLatexOperators);
                    setState(() => _editorSettings = updated);
                    await EditorSettingsService.saveSettings(updated);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Operators reset to default'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.restore_rounded, size: 16),
                  label: const Text('Reset Defaults'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openGitHubUrl(BuildContext context) async {
    const url = 'https://github.com/yingongsui/PDFREOR';
    try {
      const channel = MethodChannel('com.yin.pdfreor/stylus');
      final success = await channel.invokeMethod<bool>('openUrl', {'url': url});
      if (success != true) {
        await Clipboard.setData(const ClipboardData(text: url));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GitHub link copied to clipboard')),
        );
      }
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: url));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GitHub link copied to clipboard')),
      );
    }
  }
}

class _AddOperatorDialog extends StatefulWidget {
  const _AddOperatorDialog();

  @override
  State<_AddOperatorDialog> createState() => _AddOperatorDialogState();
}

class _AddOperatorDialogState extends State<_AddOperatorDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _controller.text.trim();
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.functions_rounded, color: Colors.blue),
          SizedBox(width: 8),
          Text('Add Math Operator'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Enter a LaTeX operator or formula snippet to add to the quick bar:',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: r'e.g. \vec{v}, \mathbb{R}, \nabla',
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            alignment: Alignment.center,
            child: Math.tex(
              text.isEmpty ? r'\dots' : text,
              textStyle: const TextStyle(fontSize: 16),
              mathStyle: MathStyle.display,
              onErrorFallback: (err) => Text(
                'Invalid: ${err.message}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: text.isEmpty ? null : () => Navigator.pop(context, text),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

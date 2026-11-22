import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../../models/pdf_file_info.dart';
import '../../widgets/app_toast.dart';

String folderDisplayName(String folderPath) {
  final baseName = p.basename(folderPath);
  return baseName.isNotEmpty ? baseName : folderPath;
}

class _ContextMenuAction {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _ContextMenuAction({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
}

void _showContextMenuSheet(
  BuildContext context, {
  required IconData headerIcon,
  required String title,
  required String subtitle,
  required List<_ContextMenuAction> actions,
}) {
  final theme = Theme.of(context);
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetDragHandle(margin: EdgeInsets.only(top: 12, bottom: 8)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        headerIcon,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final action in actions)
                ListTile(
                  leading: Icon(action.icon),
                  title: Text(action.title),
                  subtitle: action.subtitle != null ? Text(action.subtitle!) : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    action.onTap();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

class SheetDragHandle extends StatelessWidget {
  final EdgeInsetsGeometry margin;

  const SheetDragHandle({
    super.key,
    this.margin = const EdgeInsets.only(bottom: 16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: margin,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

Future<String?> showRenamePdfDialog(
  BuildContext context, {
  required String initialName,
  required String extensionText,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => RenameFileDialog(
      initialName: initialName,
      extensionText: extensionText,
    ),
  );
}

void showAddPdfOptionsSheet(
  BuildContext context, {
  required VoidCallback onAddFiles,
  required VoidCallback onAddFolder,
}) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetDragHandle(),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.note_add_rounded, color: theme.colorScheme.primary),
                ),
                title: const Text('Add PDF Files'),
                subtitle: const Text('Pick one or more PDF files to add to library'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onAddFiles();
                },
              ),
              const SizedBox(height: 6),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.create_new_folder_rounded, color: theme.colorScheme.secondary),
                ),
                title: const Text('Add Folder'),
                subtitle: const Text('Scan and add all PDFs from a selected folder'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onAddFolder();
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

void showPdfFileDetailsDialog(BuildContext context, PdfFileInfo file) {
  final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue),
          SizedBox(width: 8),
          Text('File Details'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDetailRow('File Name', file.name),
            const Divider(),
            _buildDetailRow('File Size', file.formattedSize),
            const Divider(),
            _buildDetailRow('Last Modified', dateFormat.format(file.lastModified)),
            const Divider(),
            _buildDetailRow('Full Path', file.path),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: file.path));
            AppToast.show(
              dialogContext,
              'Path copied to clipboard',
              icon: Icons.check_circle_outline_rounded,
            );
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy Path'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Widget _buildDetailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    ),
  );
}

void showPdfFileContextMenu(
  BuildContext context, {
  required PdfFileInfo file,
  required int selectedCount,
  required VoidCallback onOpenReader,
  required VoidCallback onRename,
  required VoidCallback onOpenExternal,
  required VoidCallback onShare,
  required VoidCallback onShowDetails,
}) {
  _showContextMenuSheet(
    context,
    headerIcon: Icons.picture_as_pdf_rounded,
    title: file.name,
    subtitle: '${file.formattedSize} • ${file.parentDirectoryName}',
    actions: [
      _ContextMenuAction(
        icon: Icons.visibility_outlined,
        title: selectedCount > 1 ? 'Open Reader ($selectedCount)' : 'Open Reader',
        onTap: onOpenReader,
      ),
      _ContextMenuAction(
        icon: Icons.drive_file_rename_outline_rounded,
        title: 'Rename',
        onTap: onRename,
      ),
      _ContextMenuAction(
        icon: Icons.open_in_new_rounded,
        title: 'Open with External App',
        onTap: onOpenExternal,
      ),
      _ContextMenuAction(
        icon: Icons.share_outlined,
        title: selectedCount > 1 ? 'Share Selected ($selectedCount)' : 'Share',
        onTap: onShare,
      ),
      _ContextMenuAction(
        icon: Icons.info_outline,
        title: 'File Info',
        onTap: onShowDetails,
      ),
    ],
  );
}

class RenameFileDialog extends StatefulWidget {
  final String initialName;
  final String extensionText;

  const RenameFileDialog({
    super.key,
    required this.initialName,
    required this.extensionText,
  });

  @override
  State<RenameFileDialog> createState() => _RenameFileDialogState();
}

class _RenameFileDialogState extends State<RenameFileDialog> {
  late final TextEditingController _controller;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.drive_file_rename_outline_rounded, color: Colors.blue),
          SizedBox(width: 8),
          Text('Rename PDF'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter new name for the document:',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'File Name',
                suffixText: widget.extensionText,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
              ),
              validator: (val) {
                final trimmed = val?.trim() ?? '';
                if (trimmed.isEmpty) {
                  return 'File name cannot be empty';
                }
                if (trimmed.contains(RegExp(r'[\\/:*?"<>|]'))) {
                  return 'Cannot contain \\ / : * ? " < > |';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Rename'),
        ),
      ],
    );
  }
}

void showFolderContextMenu(
  BuildContext context, {
  required String folderName,
  required String folderPath,
  required int fileCount,
  required bool isCollapsed,
  required VoidCallback onToggleCollapse,
  required VoidCallback onHideFolder,
}) {
  _showContextMenuSheet(
    context,
    headerIcon: Icons.folder_rounded,
    title: folderName,
    subtitle: '$fileCount ${fileCount == 1 ? 'file' : 'files'} • $folderPath',
    actions: [
      _ContextMenuAction(
        icon: isCollapsed ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
        title: isCollapsed ? 'Expand Folder' : 'Collapse Folder',
        onTap: onToggleCollapse,
      ),
      _ContextMenuAction(
        icon: Icons.visibility_off_outlined,
        title: 'Hide Folder',
        subtitle: 'Stop showing PDFs in this folder on the home screen',
        onTap: onHideFolder,
      ),
    ],
  );
}

Future<void> showHiddenFoldersDialog(
  BuildContext context, {
  required Set<String> hiddenFolders,
  required Future<void> Function(String folderPath) onUnhideFolder,
  required Future<void> Function() onUnhideAll,
}) {
  final currentHidden = hiddenFolders.toList()..sort();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: const Text('Hidden Folders'),
            content: SizedBox(
              width: 440,
              child: currentHidden.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No hidden folders.',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: currentHidden.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final folderPath = currentHidden[index];
                          final folderName = folderDisplayName(folderPath);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.folder_off_outlined,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            title: Text(
                              folderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              folderPath,
                              style: const TextStyle(fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: TextButton(
                              onPressed: () async {
                                await onUnhideFolder(folderPath);
                                setDialogState(() {
                                  currentHidden.remove(folderPath);
                                });
                              },
                              child: const Text('Show'),
                            ),
                          );
                        },
                      ),
                    ),
            ),
            actions: [
              if (currentHidden.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await onUnhideAll();
                    setDialogState(() {
                      currentHidden.clear();
                    });
                  },
                  child: const Text('Show All'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    },
  );
}

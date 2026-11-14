import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/pdf_file_info.dart';

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
                subtitle: const Text('Scan and add all PDFs from a folder or SD card directory'),
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
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(content: Text('Path copied to clipboard')),
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
                        Icons.picture_as_pdf_rounded,
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
                            file.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${file.formattedSize} • ${file.parentDirectoryName}',
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
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(
                  selectedCount > 1 ? 'Open Reader ($selectedCount)' : 'Open Reader',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onOpenReader();
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline_rounded),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onRename();
                },
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Open with External App'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onOpenExternal();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: Text(
                  selectedCount > 1 ? 'Share Selected ($selectedCount)' : 'Share',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onShare();
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('File Info'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onShowDetails();
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

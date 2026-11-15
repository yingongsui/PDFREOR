import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'settings_widgets.dart';

class HiddenFoldersCard extends StatelessWidget {
  final List<String> hiddenFolders;
  final VoidCallback onAddFolder;
  final ValueChanged<String> onRemoveFolder;
  final VoidCallback onClearAll;

  const HiddenFoldersCard({
    super.key,
    required this.hiddenFolders,
    required this.onAddFolder,
    required this.onRemoveFolder,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = hiddenFolders.length;

    return SettingsCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SettingsIconBadge(icon: Icons.folder_off_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hidden Folders',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      count == 0
                          ? 'Hide folders with unwanted PDFs from the library'
                          : '$count hidden ${count == 1 ? 'folder' : 'folders'} • Subfolders also excluded',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hiddenFolders.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < hiddenFolders.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: 12,
                        endIndent: 12,
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    _HiddenFolderRow(
                      folderPath: hiddenFolders[i],
                      onUnhide: () => onRemoveFolder(hiddenFolders[i]),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (hiddenFolders.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: onClearAll,
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: const Text('Clear All'),
                ),
                const SizedBox(width: 8),
              ],
              FilledButton.tonalIcon(
                onPressed: onAddFolder,
                icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                label: const Text('Add Folder'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HiddenFolderRow extends StatelessWidget {
  final String folderPath;
  final VoidCallback onUnhide;

  const _HiddenFolderRow({
    required this.folderPath,
    required this.onUnhide,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseName = p.basename(folderPath);
    final displayName = baseName.isNotEmpty ? baseName : folderPath;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  folderPath,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.visibility_rounded, size: 18),
            tooltip: 'Unhide folder',
            visualDensity: VisualDensity.compact,
            onPressed: onUnhide,
          ),
        ],
      ),
    );
  }
}

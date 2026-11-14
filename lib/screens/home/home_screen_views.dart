part of '../home_screen.dart';

extension _HomeScreenViews on _HomeScreenState {
  List<MapEntry<String, List<PdfFileInfo>>> get _sortedGroupedEntries {
    return _cachedGroupedEntries ??= _computeSortedGroupedEntries();
  }

  List<MapEntry<String, List<PdfFileInfo>>> _computeSortedGroupedEntries() {
    final Map<String, List<PdfFileInfo>> groups = {};
    for (final file in _filteredFiles) {
      final folder = file.parentDirectoryPath.isNotEmpty
          ? file.parentDirectoryPath
          : 'Root Directory';
      groups.putIfAbsent(folder, () => []).add(file);
    }

    final entries = groups.entries.toList();

    final lowerNames = <String, String>{};
    final lowerPaths = <String, String>{};
    final latestDates = <String, DateTime>{};

    for (final e in entries) {
      final base = p.basename(e.key);
      lowerNames[e.key] = (base.isNotEmpty ? base : e.key).toLowerCase();
      lowerPaths[e.key] = e.key.toLowerCase();
      if (_folderSortType == FolderSortType.dateDesc ||
          _folderSortType == FolderSortType.dateAsc) {
        if (e.value.isEmpty) {
          latestDates[e.key] = DateTime.fromMillisecondsSinceEpoch(0);
        } else {
          var latest = e.value.first.lastModified;
          for (int i = 1; i < e.value.length; i++) {
            final d = e.value[i].lastModified;
            if (d.isAfter(latest)) latest = d;
          }
          latestDates[e.key] = latest;
        }
      }
    }

    switch (_folderSortType) {
      case FolderSortType.nameAsc:
        entries.sort((a, b) => lowerNames[a.key]!.compareTo(lowerNames[b.key]!));
        break;
      case FolderSortType.nameDesc:
        entries.sort((a, b) => lowerNames[b.key]!.compareTo(lowerNames[a.key]!));
        break;
      case FolderSortType.pathAsc:
        entries.sort((a, b) => lowerPaths[a.key]!.compareTo(lowerPaths[b.key]!));
        break;
      case FolderSortType.pathDesc:
        entries.sort((a, b) => lowerPaths[b.key]!.compareTo(lowerPaths[a.key]!));
        break;
      case FolderSortType.fileCountDesc:
        entries.sort((a, b) {
          final cmp = b.value.length.compareTo(a.value.length);
          return cmp != 0 ? cmp : lowerNames[a.key]!.compareTo(lowerNames[b.key]!);
        });
        break;
      case FolderSortType.fileCountAsc:
        entries.sort((a, b) {
          final cmp = a.value.length.compareTo(b.value.length);
          return cmp != 0 ? cmp : lowerNames[a.key]!.compareTo(lowerNames[b.key]!);
        });
        break;
      case FolderSortType.dateDesc:
        entries.sort((a, b) {
          final cmp = latestDates[b.key]!.compareTo(latestDates[a.key]!);
          return cmp != 0 ? cmp : lowerNames[a.key]!.compareTo(lowerNames[b.key]!);
        });
        break;
      case FolderSortType.dateAsc:
        entries.sort((a, b) {
          final cmp = latestDates[a.key]!.compareTo(latestDates[b.key]!);
          return cmp != 0 ? cmp : lowerNames[a.key]!.compareTo(lowerNames[b.key]!);
        });
        break;
    }

    return entries;
  }

  Widget _buildFoldersHeaderBar(
    List<MapEntry<String, List<PdfFileInfo>>> groupedEntries,
    ThemeData theme,
  ) {
    final allFolderPaths = groupedEntries.map((e) => e.key).toList();
    final allCollapsed = allFolderPaths.isNotEmpty &&
        allFolderPaths.every((p) => _collapsedFolders.contains(p));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Icon(
            Icons.folder_copy_rounded,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            '${groupedEntries.length} ${groupedEntries.length == 1 ? 'Folder' : 'Folders'} • ${_filteredFiles.length} PDFs',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // Fixed-size Collapse All / Expand All Toggle
          SizedBox(
            width: 100,
            height: 28,
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _toggleAllFolders(allFolderPaths),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 4),
                      Text(
                        allCollapsed ? 'Expand All' : 'Collapse All',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        allCollapsed ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderBanner(
    String folderPath,
    List<PdfFileInfo> files,
    ThemeData theme,
  ) {
    final isCollapsed = _collapsedFolders.contains(folderPath);
    final baseName = p.basename(folderPath);
    final folderName = baseName.isNotEmpty ? baseName : folderPath;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _toggleFolderCollapse(folderPath),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isCollapsed ? Icons.folder_rounded : Icons.folder_open_rounded,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        folderName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        folderPath,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_clipboardFiles.isNotEmpty) ...[
                  IconButton(
                    icon: Icon(
                      Icons.paste_rounded,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    tooltip: _isCutMode ? 'Move files to this folder' : 'Paste files to this folder',
                    onPressed: () => _pasteFilesToFolder(folderPath),
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '${files.length} ${files.length == 1 ? 'file' : 'files'}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  isCollapsed
                      ? Icons.keyboard_arrow_right_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading && _allFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _scanStatusText,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      );
    }

    if (_filteredFiles.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 72,
                  color: theme.colorScheme.outline.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  _allFiles.isEmpty ? 'No PDF Files Found' : 'No Matching PDFs Found',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _allFiles.isEmpty
                      ? 'Pull down to refresh and rescan, or use the buttons below to import PDF files.'
                      : 'Please try searching with different keywords.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _importFiles,
                      icon: const Icon(Icons.file_open_rounded),
                      label: const Text('Pick Files'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickAndScanDirectory,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('Pick Folder'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final groupedEntries = _sortedGroupedEntries;
    final openPaths = PdfTabManager.instance.openTabs.map((t) => t.path).toSet();
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        for (final entry in groupedEntries) ...[
          SliverToBoxAdapter(
            child: _buildFolderBanner(entry.key, entry.value, theme),
          ),
          if (!_collapsedFolders.contains(entry.key)) ...[
            if (_viewMode == PdfViewMode.thumbnail)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final file = entry.value[index];
                      return PdfThumbnailCard(
                        key: ValueKey(file.path),
                        file: file,
                        isOpen: openPaths.contains(file.path),
                        isSelectionMode: _isSelectionMode,
                        isSelected: _selectedFilePaths.contains(file.path),
                        onTap: () => _onFileTap(file),
                        onLongPress: () => _onFileLongPress(file),
                      );
                    },
                    childCount: entry.value.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(top: 2, bottom: 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final file = entry.value[index];
                      return PdfListTile(
                        key: ValueKey(file.path),
                        file: file,
                        isOpen: openPaths.contains(file.path),
                        isSelectionMode: _isSelectionMode,
                        isSelected: _selectedFilePaths.contains(file.path),
                        onTap: () => _onFileTap(file),
                        onLongPress: () => _onFileLongPress(file),
                      );
                    },
                    childCount: entry.value.length,
                  ),
                ),
              ),
          ],
        ],
        const SliverPadding(
          padding: EdgeInsets.only(bottom: 80),
        ),
      ],
    );
  }
}

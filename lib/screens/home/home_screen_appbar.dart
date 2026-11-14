part of '../home_screen.dart';

extension _HomeScreenAppBar on _HomeScreenState {
  PreferredSizeWidget _buildHomeAppBar(ThemeData theme) {
    return _isSelectionMode
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Exit Selection',
                  onPressed: _exitSelectionMode,
                ),
                title: Container(
                  width: 28,  // Square badge size
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1), // Background color
                    border: Border.all(
                      color: Colors.blue, // Border color
                      width: 1.5,         // Border width
                    ),
                    borderRadius: BorderRadius.circular(6), // Border radius
                  ),
                  child: Text(
                    '${_selectedFilePaths.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue, // Text color
                      fontSize: 14,
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      _selectedFilePaths.length == _filteredFiles.length && _filteredFiles.isNotEmpty
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                    ),
                    tooltip: _selectedFilePaths.length == _filteredFiles.length && _filteredFiles.isNotEmpty
                        ? 'Deselect All'
                        : 'Select All',
                    onPressed: _toggleSelectAll,
                  ),
                  if (_selectedFilePaths.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.copy_rounded),
                      tooltip: 'Copy',
                      onPressed: _copySelectedFiles,
                    ),
                  if (_selectedFilePaths.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.content_cut_rounded),
                      tooltip: 'Cut',
                      onPressed: _cutSelectedFiles,
                    ),
                  if (_selectedFilePaths.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                      tooltip: 'Delete',
                      onPressed: _deleteSelectedFiles,
                    ),
                  if (_selectedFilePaths.isNotEmpty)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded),
                      tooltip: 'More Options',
                      onSelected: (val) {
                        final selectedFiles = _allFiles
                            .where((f) => _selectedFilePaths.contains(f.path))
                            .toList();
                        if (selectedFiles.isEmpty) return;
                        final singleFile = selectedFiles.first;
                        switch (val) {
                          case 'open':
                            _openSelectedFilesInReader();
                            break;
                          case 'rename':
                            _promptRenameFile(singleFile);
                            break;
                          case 'external':
                            _openExternal(singleFile);
                            break;
                          case 'share':
                            _shareSelectedFiles();
                            break;
                          case 'details':
                            _showFileDetails(singleFile);
                            break;
                        }
                      },
                      itemBuilder: (context) {
                        if (_selectedFilePaths.length == 1) {
                          return const [
                            PopupMenuItem(
                              value: 'open',
                              child: Row(
                                children: [
                                  Icon(Icons.visibility_outlined, size: 18),
                                  SizedBox(width: 10),
                                  Text('Open Reader'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'rename',
                              child: Row(
                                children: [
                                  Icon(Icons.drive_file_rename_outline_rounded, size: 18),
                                  SizedBox(width: 10),
                                  Text('Rename'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'external',
                              child: Row(
                                children: [
                                  Icon(Icons.open_in_new_rounded, size: 18),
                                  SizedBox(width: 10),
                                  Text('Open with External App'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'share',
                              child: Row(
                                children: [
                                  Icon(Icons.share_outlined, size: 18),
                                  SizedBox(width: 10),
                                  Text('Share'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'details',
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 18),
                                  SizedBox(width: 10),
                                  Text('File Info'),
                                ],
                              ),
                            ),
                          ];
                        } else {
                          return [
                            PopupMenuItem(
                              value: 'open',
                              child: Row(
                                children: [
                                  const Icon(Icons.visibility_outlined, size: 18),
                                  const SizedBox(width: 10),
                                  Text('Open Reader (${_selectedFilePaths.length})'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'share',
                              child: Row(
                                children: [
                                  Icon(Icons.share_outlined, size: 18),
                                  SizedBox(width: 10),
                                  Text('Share Selected'),
                                ],
                              ),
                            ),
                          ];
                        }
                      },
                    ),
                ],
              )
            : AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search PDF files...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                style: const TextStyle(fontSize: 16),
                onChanged: (_) {
                  _searchDebounceTimer?.cancel();
                  _searchDebounceTimer = Timer(const Duration(milliseconds: 140), () {
                    if (!mounted) return;
                    _refresh(() {
                      _applyFilterAndSort();
                    });
                  });
                },
              )
            : Row(
                children: [
                  const Text('PDFREOR', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  if (!_isLoading && _allFiles.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_filteredFiles.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
        actions: [
          // Search button / Clear button
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close Search',
              onPressed: () {
                _refresh(() {
                  _isSearching = false;
                  _searchController.clear();
                  _applyFilterAndSort();
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: 'Search',
              onPressed: () {
                _refresh(() {
                  _isSearching = true;
                });
              },
            ),

          // View Mode Selector (Thumbnail vs List)
          IconButton(
            icon: Icon(
              _viewMode == PdfViewMode.thumbnail
                  ? Icons.grid_view_rounded
                  : Icons.view_list_rounded,
            ),
            tooltip: _viewMode == PdfViewMode.thumbnail
                ? 'Grid View'
                : 'List View',
            onPressed: () {
              _refresh(() {
                _viewMode = _viewMode == PdfViewMode.thumbnail
                    ? PdfViewMode.list
                    : PdfViewMode.thumbnail;
              });
            },
          ),

          // Sort Menu
          IconButton(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort Options',
            onPressed: _showSortOptionsSheet,
          ),

          // Settings Button
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              if (!mounted) return;
              final granted = await _scannerService.hasStoragePermission();
              if (!mounted) return;
              if (granted != _hasPermission) {
                _refresh(() => _hasPermission = granted);
                if (granted && _allFiles.isEmpty) {
                  _startScan();
                }
              }
            },
          ),
        ],
      );
  }
}

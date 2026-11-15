part of '../home_screen.dart';

extension _HomeScreenActions on _HomeScreenState {
  void _showHomeSnackBar(
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 4),
    bool replaceCurrent = false,
    SnackBarAction? action,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (replaceCurrent) {
      messenger.hideCurrentSnackBar();
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
        action: action,
      ),
    );
  }

  List<PdfFileInfo> get _selectedFiles =>
      _allFiles.where((f) => _selectedFilePaths.contains(f.path)).toList();

  void _mergeDiscoveredFiles(List<PdfFileInfo> files) {
    final existingPaths = _allFiles.map((f) => f.path).toSet();
    for (final f in files) {
      if (existingPaths.add(f.path)) {
        _allFiles.add(f);
      }
    }
  }

  Future<void> _checkPermissionAndScan() async {
    final granted = await _scannerService.hasStoragePermission();
    if (!mounted) return;
    _refresh(() {
      _hasPermission = granted;
    });

    if (granted) {
      _startScan();
    } else {
      // Prompt for permission automatically once
      final requestResult = await _scannerService.requestStoragePermission();
      if (!mounted) return;
      _refresh(() {
        _hasPermission = requestResult;
      });
      if (requestResult) {
        _startScan();
      }
    }
  }

  Future<void> _requestPermissionManually() async {
    final result = await _scannerService.requestStoragePermission();
    if (!mounted) return;
    _refresh(() {
      _hasPermission = result;
    });
    if (result) {
      _startScan();
    } else {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Storage Permission Required'),
            content: const Text(
              'All-files access permission is required to discover and read PDF documents on your device. Please grant it in system settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  _scannerService.openSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _startScan() async {
    if (_isLoading) return;

    _refresh(() {
      _isLoading = true;
      _scanStatusText = 'Scanning device storage...';
    });

    try {
      final files = await _scannerService.scanStorage();

      if (mounted) {
        _refresh(() {
          _allFiles = files;
          _isLoading = false;
          _applyFilterAndSort();
        });
      }
    } catch (e, stack) {
      debugPrint('Scan error: $e\n$stack');
      if (mounted) {
        _refresh(() {
          _isLoading = false;
        });
        _showHomeSnackBar('Scan error: $e');
      }
    }
  }

  Future<void> _pickAndScanDirectory() async {
    final path = await _scannerService.pickDirectory();
    if (path == null) return;

    if (PdfScannerService.isPathInHiddenFolders(path, _hiddenFolders)) {
      _showHomeSnackBar(
        'Selected folder is currently hidden in Settings',
        replaceCurrent: true,
      );
      return;
    }

    _refresh(() {
      _isLoading = true;
      _scanStatusText = 'Scanning selected folder...';
    });

    try {
      final files = await _scannerService.scanCustomDirectory(path);
      if (mounted) {
        _refresh(() {
          _mergeDiscoveredFiles(files);
          _isLoading = false;
          _applyFilterAndSort();
        });
        _showHomeSnackBar('Found ${files.length} PDF files');
      }
    } catch (e) {
      if (mounted) {
        _refresh(() {
          _isLoading = false;
        });
        _showHomeSnackBar('Scan failed: $e');
      }
    }
  }

  Future<void> _importFiles() async {
    final files = await _scannerService.pickPdfFiles();
    if (files.isNotEmpty) {
      await _scannerService.addImportedFilePaths(files.map((f) => f.path));
      if (!mounted) return;
      _refresh(() {
        _mergeDiscoveredFiles(files);
        _applyFilterAndSort();
      });
      _showHomeSnackBar('Imported ${files.length} files');
    }
  }


  void _applyFilterAndSort() {
    final query = _searchController.text.trim().toLowerCase();
    final visibleFiles = _hiddenFolders.isEmpty
        ? _allFiles
        : _allFiles
              .where(
                (f) => !PdfScannerService.isPathInHiddenFolders(
                  f.path,
                  _hiddenFolders,
                ),
              )
              .toList();
    List<PdfFileInfo> list;

    if (query.isNotEmpty) {
      list = visibleFiles.where((f) => f.name.toLowerCase().contains(query)).toList();
    } else {
      list = List.from(visibleFiles);
    }

    switch (_sortType) {
      case SortType.dateDesc:
        list.sort((a, b) => b.lastModified.compareTo(a.lastModified));
        break;
      case SortType.dateAsc:
        list.sort((a, b) => a.lastModified.compareTo(b.lastModified));
        break;
      case SortType.nameAsc:
      case SortType.nameDesc:
        final lowerNames = <String, String>{
          for (final f in list) f.path: f.name.toLowerCase(),
        };
        final descending = _sortType == SortType.nameDesc;
        list.sort((a, b) {
          final cmp = lowerNames[a.path]!.compareTo(lowerNames[b.path]!);
          return descending ? -cmp : cmp;
        });
        break;
      case SortType.sizeDesc:
        list.sort((a, b) => b.sizeInBytes.compareTo(a.sizeInBytes));
        break;
      case SortType.sizeAsc:
        list.sort((a, b) => a.sizeInBytes.compareTo(b.sizeInBytes));
        break;
    }

    _filteredFiles = list;
    _cachedGroupedEntries = null;
  }

  void _pushViewerRoute(PdfFileInfo activeFile) {
    if (_isViewerRouteOpen) return;
    _isViewerRouteOpen = true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(file: activeFile),
      ),
    ).whenComplete(() {
      _isViewerRouteOpen = false;
      if (mounted) _refresh(() {});
    });
  }

  void _openPdfViewer(PdfFileInfo file) {
    PdfTabManager.instance.openTab(file);
    _pushViewerRoute(file);
  }

  Future<void> _openExternal(PdfFileInfo file) async {
    try {
      final res = await OpenFilex.open(file.path);
      if (res.type != ResultType.done) {
        _showHomeSnackBar('Unable to open: ${res.message}');
      }
    } catch (e) {
      _showHomeSnackBar('Open error: $e');
    }
  }

  Future<void> _shareFile(PdfFileInfo file) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: file.name,
        ),
      );
    } catch (e) {
      _showHomeSnackBar('Share failed: $e');
    }
  }

  Future<void> _promptRenameFile(PdfFileInfo file) async {
    HapticFeedback.mediumImpact();
    final ext = p.extension(file.path);
    final baseName = p.basenameWithoutExtension(file.path);

    final newBaseName = await showRenamePdfDialog(context, initialName: baseName, extensionText: ext);

    if (newBaseName == null || newBaseName.isEmpty || newBaseName == baseName) return;

    final newFileName = '$newBaseName$ext';
    final parentDir = File(file.path).parent;
    final newPath = p.join(parentDir.path, newFileName);

    if (await File(newPath).exists()) {
      _showHomeSnackBar(
        'A file named "$newFileName" already exists.',
        backgroundColor: Colors.red.shade700,
      );
      return;
    }

    try {
      final oldFile = File(file.path);
      final renamedFile = await oldFile.rename(newPath);

      final updatedFileInfo = PdfFileInfo.fromFile(renamedFile);

      await _scannerService.renameImportedFilePath(file.path, newPath);

      // Invalidate old thumbnail cache and update open tabs / reading progress
      PdfThumbnailService.instance.invalidate(file.path);
      PdfTabManager.instance.renameTab(file.path, updatedFileInfo);

      // Update in memory file list
      if (!mounted) return;
      _refresh(() {
        final idx = _allFiles.indexWhere((f) => f.path == file.path);
        if (idx != -1) {
          _allFiles[idx] = updatedFileInfo;
        }
        _applyFilterAndSort();
      });

      _showHomeSnackBar(
        'Renamed to "$newFileName"',
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      _showHomeSnackBar(
        'Failed to rename file: $e',
        backgroundColor: Colors.red.shade700,
      );
    }
  }


  void _moveSelectionToClipboard({required bool isCut}) {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    _refresh(() {
      _clipboardFiles = files;
      _isCutMode = isCut;
      _isSelectionMode = false;
      _selectedFilePaths.clear();
    });
    HapticFeedback.selectionClick();
    final String message;
    if (isCut) {
      message = files.length == 1
          ? 'Cut "${files.first.name}". Tap Paste on any folder banner.'
          : 'Cut ${files.length} files. Tap Paste on any folder banner.';
    } else {
      message = files.length == 1
          ? 'Copied "${files.first.name}" to clipboard'
          : 'Copied ${files.length} files to clipboard';
    }
    _showHomeSnackBar(
      message,
      duration: const Duration(seconds: 2),
      replaceCurrent: true,
    );
  }

  void _copySelectedFiles() => _moveSelectionToClipboard(isCut: false);

  void _cutSelectedFiles() => _moveSelectionToClipboard(isCut: true);

  Future<void> _pasteFilesToFolder(String targetFolderPath) async {
    if (_clipboardFiles.isEmpty) return;

    final targetDir = Directory(targetFolderPath);
    if (!await targetDir.exists()) {
      try {
        await targetDir.create(recursive: true);
      } catch (e) {
        _showHomeSnackBar(
          'Cannot write to folder: $e',
          backgroundColor: Colors.red,
          replaceCurrent: true,
        );
        return;
      }
    }

    int successCount = 0;
    int failedCount = 0;
    final isCut = _isCutMode;
    final filesToProcess = List<PdfFileInfo>.from(_clipboardFiles);

    for (final sourceInfo in filesToProcess) {
      final sourcePath = sourceInfo.path;
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        failedCount++;
        continue;
      }

      final baseName = p.basenameWithoutExtension(sourcePath);
      final ext = p.extension(sourcePath);

      try {
        if (isCut) {
          final destPath = p.join(targetDir.path, p.basename(sourcePath));
          if (destPath != sourcePath) {
            String finalDestPath = destPath;
            int counter = 1;
            while (await File(finalDestPath).exists()) {
              finalDestPath = p.join(targetDir.path, '$baseName ($counter)$ext');
              counter++;
            }
            try {
              await sourceFile.rename(finalDestPath);
            } on FileSystemException {
              await sourceFile.copy(finalDestPath);
              await sourceFile.delete();
            }
            await _scannerService.renameImportedFilePath(sourcePath, finalDestPath);
            PdfThumbnailService.instance.invalidate(sourcePath);
            PdfTabManager.instance.renameTab(
              sourcePath,
              PdfFileInfo.fromFile(File(finalDestPath)),
            );
            successCount++;
          }
        } else {
          String destPath = p.join(targetDir.path, p.basename(sourcePath));
          if (await File(destPath).exists()) {
            destPath = p.join(targetDir.path, '$baseName (Copy)$ext');
            int counter = 2;
            while (await File(destPath).exists()) {
              destPath = p.join(targetDir.path, '$baseName (Copy $counter)$ext');
              counter++;
            }
          }
          await sourceFile.copy(destPath);
          successCount++;
        }
      } catch (_) {
        failedCount++;
      }
    }

    if (isCut) {
      _refresh(() {
        _clipboardFiles.clear();
        _isCutMode = false;
      });
    }

    if (!mounted) return;
    if (successCount > 0) {
      await _startScan();
    }

    if (successCount == 0 && failedCount == 0) {
      return;
    }

    final actionVerb = isCut ? 'Moved' : 'Copied';
    final String message;
    final Color backgroundColor;
    if (successCount == 0) {
      message = 'Failed to ${isCut ? 'move' : 'copy'} $failedCount file(s)';
      backgroundColor = Colors.red;
    } else if (failedCount > 0) {
      message = '$actionVerb $successCount file(s), $failedCount failed';
      backgroundColor = Colors.orange;
    } else {
      message = successCount == 1
          ? '$actionVerb 1 file successfully'
          : '$actionVerb $successCount files successfully';
      backgroundColor = Colors.green;
    }

    _showHomeSnackBar(
      message,
      backgroundColor: backgroundColor,
      duration: const Duration(seconds: 2),
      replaceCurrent: true,
    );
  }

  void _onFileTap(PdfFileInfo file) {
    if (_isSelectionMode) {
      _refresh(() {
        if (_selectedFilePaths.contains(file.path)) {
          _selectedFilePaths.remove(file.path);
          if (_selectedFilePaths.isEmpty) {
            _isSelectionMode = false;
          }
        } else {
          _selectedFilePaths.add(file.path);
        }
      });
    } else {
      _openPdfViewer(file);
    }
  }

  void _onFileLongPress(PdfFileInfo file) {
    HapticFeedback.mediumImpact();
    if (!_isSelectionMode) {
      _refresh(() {
        _isSelectionMode = true;
        _selectedFilePaths.add(file.path);
      });
    } else {
      _showFileContextMenu(file);
    }
  }

  void _exitSelectionMode() {
    _refresh(() {
      _isSelectionMode = false;
      _selectedFilePaths.clear();
    });
  }

  void _toggleSelectAll() {
    final allFilteredSelected = _filteredFiles.isNotEmpty &&
        _filteredFiles.every((f) => _selectedFilePaths.contains(f.path));
    _refresh(() {
      if (allFilteredSelected) {
        _selectedFilePaths.clear();
        _isSelectionMode = false;
      } else {
        _selectedFilePaths.clear();
        _selectedFilePaths.addAll(_filteredFiles.map((f) => f.path));
      }
    });
  }

  void _openSelectedFilesInReader([PdfFileInfo? targetFile]) {
    final selectedFiles = _selectedFiles;
    if (targetFile != null && !selectedFiles.any((f) => f.path == targetFile.path)) {
      selectedFiles.add(targetFile);
    }
    if (selectedFiles.isEmpty) return;

    final activeFile = targetFile ?? selectedFiles.first;
    PdfTabManager.instance.openMultipleTabs(selectedFiles, activePath: activeFile.path);
    _exitSelectionMode();
    _pushViewerRoute(activeFile);
  }

  Future<void> _shareSelectedFiles() async {
    final filesToShare = _selectedFiles.map((f) => XFile(f.path)).toList();
    if (filesToShare.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: filesToShare,
          text: '${filesToShare.length} PDF files',
        ),
      );
    } catch (e) {
      _showHomeSnackBar('Share failed: $e');
    }
  }

  Future<void> _deleteSelectedFiles() async {
    final count = _selectedFilePaths.length;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(count == 1 ? 'Delete File' : 'Delete $count Files'),
        content: Text(
          count == 1
              ? 'Are you sure you want to delete this PDF file from storage?'
              : 'Are you sure you want to delete these $count PDF files from storage?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final deletedPaths = <String>{};
      for (final path in _selectedFilePaths.toList()) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
          deletedPaths.add(path);
          PdfThumbnailService.instance.invalidate(path);
          ReadingProgressService.instance.removePath(path);
          PdfTabManager.instance.closeTabByPath(path);
        } catch (_) {}
      }
      await _scannerService.removeImportedFilePaths(deletedPaths);
      if (mounted) {
        _refresh(() {
          _clipboardFiles.removeWhere((item) => deletedPaths.contains(item.path));
          if (_clipboardFiles.isEmpty) {
            _isCutMode = false;
          }
          _allFiles.removeWhere((f) => deletedPaths.contains(f.path));
          _isSelectionMode = false;
          _selectedFilePaths.clear();
          _applyFilterAndSort();
        });
      }
    }
  }


  void _setFolderSort(FolderSortType type) {
    _refresh(() {
      _folderSortType = type;
      _cachedGroupedEntries = null;
    });
    _scannerService.setFolderSort(type.name);
  }

  void _setFileSort(SortType type) {
    _refresh(() {
      _sortType = type;
      _applyFilterAndSort();
    });
    _scannerService.setFileSort(type.name);
  }

  void _toggleFolderCollapse(String folderPath) {
    final willCollapse = !_collapsedFolders.contains(folderPath);
    _refresh(() {
      if (willCollapse) {
        _collapsedFolders.add(folderPath);
      } else {
        _collapsedFolders.remove(folderPath);
      }
    });
    _scannerService.setFolderCollapsed(folderPath, willCollapse);
  }

  void _toggleAllFolders(List<String> allFolders) {
    if (allFolders.isEmpty) return;
    final allCollapsed = allFolders.every((f) => _collapsedFolders.contains(f));
    _refresh(() {
      if (allCollapsed) {
        _collapsedFolders.removeAll(allFolders);
      } else {
        _collapsedFolders.addAll(allFolders);
      }
    });
    _scannerService.setAllFoldersCollapsed(allFolders, !allCollapsed);
  }

  void _showAddOptions() {
    showAddPdfOptionsSheet(
      context,
      onAddFiles: _importFiles,
      onAddFolder: _pickAndScanDirectory,
    );
  }

  void _showFileDetails(PdfFileInfo file) {
    showPdfFileDetailsDialog(context, file);
  }

  void _showFileContextMenu(PdfFileInfo file) {
    showPdfFileContextMenu(
      context,
      file: file,
      selectedCount: _selectedFilePaths.length,
      onOpenReader: () => _openSelectedFilesInReader(file),
      onRename: () => _promptRenameFile(file),
      onOpenExternal: () => _openExternal(file),
      onShare: () {
        if (_selectedFilePaths.length > 1) {
          _shareSelectedFiles();
        } else {
          _shareFile(file);
        }
      },
      onShowDetails: () => _showFileDetails(file),
    );
  }

  void _showFolderContextMenu(String folderPath, List<PdfFileInfo> files) {
    HapticFeedback.mediumImpact();
    final normalized = PdfScannerService.normalizeFolderPath(folderPath);
    final baseName = p.basename(folderPath);
    final folderName = baseName.isNotEmpty ? baseName : folderPath;
    final canHide = normalized.isNotEmpty &&
        folderPath != 'Root Directory' &&
        normalized != '/' &&
        normalized != Platform.pathSeparator;

    showPdfFolderContextMenu(
      context,
      folderName: folderName,
      folderPath: folderPath,
      fileCount: files.length,
      isCollapsed: _collapsedFolders.contains(folderPath),
      canHide: canHide,
      onToggleCollapse: () => _toggleFolderCollapse(folderPath),
      onHideFolder: () => _hideFolder(normalized, folderName),
    );
  }

  Future<void> _hideFolder(String folderPath, String folderName) async {
    _refresh(() {
      _hiddenFolders.add(folderPath);
      _selectedFilePaths.removeWhere(
        (path) => PdfScannerService.isPathInHiddenFolders(path, [folderPath]),
      );
      if (_selectedFilePaths.isEmpty) {
        _isSelectionMode = false;
      }
      _applyFilterAndSort();
    });
    await _scannerService.addHiddenFolder(folderPath);
    _showHomeSnackBar(
      'Hid "$folderName"',
      replaceCurrent: true,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => _unhideFolder(folderPath),
      ),
    );
  }

  Future<void> _unhideFolder(String folderPath) async {
    _refresh(() {
      _hiddenFolders.remove(folderPath);
      _applyFilterAndSort();
    });
    await _scannerService.removeHiddenFolder(folderPath);
  }

  void _showSortOptionsSheet() {
    showHomeSortOptionsSheet(
      context,
      initialFolderSort: _folderSortType,
      initialFileSort: _sortType,
      onFolderSortChanged: _setFolderSort,
      onFileSortChanged: _setFileSort,
    );
  }
}

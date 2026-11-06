import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../models/pdf_file_info.dart';
import '../services/pdf_scanner_service.dart';
import '../services/pdf_tab_manager.dart';
import '../services/pdf_thumbnail_service.dart';
import '../widgets/pdf_list_tile.dart';
import '../widgets/pdf_thumbnail_card.dart';
import 'pdf_viewer_screen.dart';
import 'settings_screen.dart';

enum PdfViewMode {
  thumbnail, // Grid / Thumbnail view
  list, // List view
}

enum SortType {
  dateDesc, // Newest modified first
  dateAsc, // Oldest modified first
  nameAsc, // Name A to Z
  nameDesc, // Name Z to A
  sizeDesc, // Largest size first
  sizeAsc, // Smallest size first
}

enum FolderSortType {
  nameAsc, // Folder name A to Z
  nameDesc, // Folder name Z to A
  pathAsc, // Folder path A to Z
  pathDesc, // Folder path Z to A
  fileCountDesc, // Most files first
  fileCountAsc, // Fewest files first
  dateDesc, // Newest modified PDF first
  dateAsc, // Oldest modified PDF first
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PdfScannerService _scannerService = PdfScannerService.instance;

  List<PdfFileInfo> _allFiles = [];
  List<PdfFileInfo> _filteredFiles = [];

  bool _isLoading = false;
  bool _hasPermission = true;
  String _scanStatusText = '';

  PdfViewMode _viewMode = PdfViewMode.thumbnail;
  SortType _sortType = SortType.dateDesc;
  FolderSortType _folderSortType = FolderSortType.nameAsc;

  final Set<String> _collapsedFolders = {};
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<PdfFileInfo> _clipboardFiles = [];
  bool _isCutMode = false;
  bool _isSelectionMode = false;
  final Set<String> _selectedFilePaths = {};

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    PdfTabManager.instance.init();
    PdfTabManager.instance.addListener(_onTabStateChanged);
    _checkPermissionAndScan();
  }

  Future<void> _loadPreferences() async {
    try {
      final collapsed = await _scannerService.getCollapsedFolders();
      final folderSortStr = await _scannerService.getFolderSort();
      final fileSortStr = await _scannerService.getFileSort();

      FolderSortType fSort = FolderSortType.nameAsc;
      for (final v in FolderSortType.values) {
        if (v.name == folderSortStr) {
          fSort = v;
          break;
        }
      }

      SortType sSort = SortType.dateDesc;
      for (final v in SortType.values) {
        if (v.name == fileSortStr) {
          sSort = v;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _collapsedFolders.clear();
          _collapsedFolders.addAll(collapsed);
          _folderSortType = fSort;
          _sortType = sSort;
          _applyFilterAndSort();
        });
      }
    } catch (_) {}
  }

  void _onTabStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PdfTabManager.instance.removeListener(_onTabStateChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissionAndScan() async {
    final granted = await _scannerService.hasStoragePermission();
    setState(() {
      _hasPermission = granted;
    });

    if (granted) {
      _startScan();
    } else {
      // Prompt for permission automatically once
      final requestResult = await _scannerService.requestStoragePermission();
      setState(() {
        _hasPermission = requestResult;
      });
      if (requestResult) {
        _startScan();
      }
    }
  }

  Future<void> _requestPermissionManually() async {
    final result = await _scannerService.requestStoragePermission();
    setState(() {
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

    setState(() {
      _isLoading = true;
      _scanStatusText = 'Scanning device storage...';
    });

    try {
      final files = await _scannerService.scanStorage(
        progressCallback: (currentFolder, foundCount) {
          if (mounted) {
            setState(() {
              _scanStatusText = 'Found $foundCount PDF files...';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _allFiles = files;
          _isLoading = false;
          _applyFilterAndSort();
        });
      }
    } catch (e, stack) {
      debugPrint('Scan error: $e\n$stack');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: $e')),
        );
      }
    }
  }

  Future<void> _pickAndScanDirectory() async {
    final path = await _scannerService.pickDirectory();
    if (path == null) return;

    setState(() {
      _isLoading = true;
      _scanStatusText = 'Scanning selected folder...';
    });

    try {
      final files = await _scannerService.scanCustomDirectory(path);
      if (mounted) {
        setState(() {
          final existingPaths = _allFiles.map((f) => f.path).toSet();
          for (final f in files) {
            if (!existingPaths.contains(f.path)) {
              _allFiles.add(f);
            }
          }
          _isLoading = false;
          _applyFilterAndSort();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Found ${files.length} PDF files')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    }
  }

  Future<void> _importFiles() async {
    final files = await _scannerService.pickPdfFiles();
    if (files.isNotEmpty) {
      await _scannerService.addImportedFilePaths(files.map((f) => f.path));
      setState(() {
        final existingPaths = _allFiles.map((f) => f.path).toSet();
        for (final f in files) {
          if (!existingPaths.contains(f.path)) {
            _allFiles.add(f);
          }
        }
        _applyFilterAndSort();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${files.length} files')),
        );
      }
    }
  }

  void _showAddOptions() {
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
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
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
                    _importFiles();
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
                    _pickAndScanDirectory();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _applyFilterAndSort() {
    final query = _searchController.text.trim().toLowerCase();
    List<PdfFileInfo> list = _allFiles;

    if (query.isNotEmpty) {
      list = list.where((f) => f.name.toLowerCase().contains(query)).toList();
    } else {
      list = List.from(_allFiles);
    }

    switch (_sortType) {
      case SortType.dateDesc:
        list.sort((a, b) => b.lastModified.compareTo(a.lastModified));
        break;
      case SortType.dateAsc:
        list.sort((a, b) => a.lastModified.compareTo(b.lastModified));
        break;
      case SortType.nameAsc:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case SortType.nameDesc:
        list.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case SortType.sizeDesc:
        list.sort((a, b) => b.sizeInBytes.compareTo(a.sizeInBytes));
        break;
      case SortType.sizeAsc:
        list.sort((a, b) => a.sizeInBytes.compareTo(b.sizeInBytes));
        break;
    }

    _filteredFiles = list;
  }

  void _openPdfViewer(PdfFileInfo file) {
    PdfTabManager.instance.openTab(file);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(file: file),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _openExternal(PdfFileInfo file) async {
    try {
      final res = await OpenFilex.open(file.path);
      if (res.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open: ${res.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Open error: $e')),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    }
  }

  Future<void> _promptRenameFile(PdfFileInfo file) async {
    HapticFeedback.mediumImpact();
    final ext = p.extension(file.path);
    final baseName = p.basenameWithoutExtension(file.path);
    final textController = TextEditingController(text: baseName);
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.drive_file_rename_outline_rounded, color: Colors.blue),
            SizedBox(width: 8),
            Text('Rename PDF'),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter new name for the document:',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: textController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'File Name',
                  suffixText: ext,
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
                onFieldSubmitted: (_) {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.pop(dialogContext, true);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final newBaseName = textController.text.trim();
    if (newBaseName == baseName) return;

    final newFileName = '$newBaseName$ext';
    final parentDir = File(file.path).parent;
    final newPath = p.join(parentDir.path, newFileName);

    if (await File(newPath).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('A file named "$newFileName" already exists.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return;
    }

    try {
      final oldFile = File(file.path);
      await oldFile.rename(newPath);

      final updatedFileInfo = PdfFileInfo(
        path: newPath,
        name: newFileName,
        sizeInBytes: file.sizeInBytes,
        lastModified: DateTime.now(),
      );

      // Invalidate old thumbnail cache
      PdfThumbnailService.instance.invalidate(file.path);

      // Update in open tabs if present
      PdfTabManager.instance.renameTab(file.path, updatedFileInfo);

      // Update in memory file list
      setState(() {
        final idx = _allFiles.indexWhere((f) => f.path == file.path);
        if (idx != -1) {
          _allFiles[idx] = updatedFileInfo;
        }
        _applyFilterAndSort();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Renamed to "$newFileName"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to rename file: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _showFileDetails(PdfFileInfo file) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Path copied to clipboard')),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Path'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _copySelectedFiles() {
    final files = _allFiles.where((f) => _selectedFilePaths.contains(f.path)).toList();
    if (files.isEmpty) return;
    setState(() {
      _clipboardFiles = files;
      _isCutMode = false;
      _isSelectionMode = false;
      _selectedFilePaths.clear();
    });
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          files.length == 1
              ? 'Copied "${files.first.name}" to clipboard'
              : 'Copied ${files.length} files to clipboard',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _cutSelectedFiles() {
    final files = _allFiles.where((f) => _selectedFilePaths.contains(f.path)).toList();
    if (files.isEmpty) return;
    setState(() {
      _clipboardFiles = files;
      _isCutMode = true;
      _isSelectionMode = false;
      _selectedFilePaths.clear();
    });
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          files.length == 1
              ? 'Cut "${files.first.name}". Tap Paste on any folder banner.'
              : 'Cut ${files.length} files. Tap Paste on any folder banner.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pasteFilesToFolder(String targetFolderPath) async {
    if (_clipboardFiles.isEmpty) return;

    final targetDir = Directory(targetFolderPath);
    if (!await targetDir.exists()) {
      try {
        await targetDir.create(recursive: true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot write to folder: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    int successCount = 0;
    final isCut = _isCutMode;
    final filesToProcess = List<PdfFileInfo>.from(_clipboardFiles);

    for (final sourceInfo in filesToProcess) {
      final sourcePath = sourceInfo.path;
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) continue;

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
            await sourceFile.copy(finalDestPath);
            await sourceFile.delete();
            PdfThumbnailService.instance.invalidate(sourcePath);
            PdfTabManager.instance.closeTabByPath(sourcePath);
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
      } catch (_) {}
    }

    if (isCut) {
      setState(() {
        _clipboardFiles.clear();
        _isCutMode = false;
      });
    }

    await _startScan();

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCut
                ? (successCount == 1 ? 'Moved 1 file successfully' : 'Moved $successCount files successfully')
                : (successCount == 1 ? 'Copied 1 file successfully' : 'Copied $successCount files successfully'),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _onFileTap(PdfFileInfo file) {
    if (_isSelectionMode) {
      setState(() {
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
      setState(() {
        _isSelectionMode = true;
        _selectedFilePaths.add(file.path);
      });
    } else {
      _showFileContextMenu(file);
    }
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedFilePaths.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedFilePaths.length == _filteredFiles.length && _filteredFiles.isNotEmpty) {
        _selectedFilePaths.clear();
        _isSelectionMode = false;
      } else {
        _selectedFilePaths.clear();
        _selectedFilePaths.addAll(_filteredFiles.map((f) => f.path));
      }
    });
  }

  void _openSelectedFilesInReader([PdfFileInfo? targetFile]) {
    final selectedFiles = _allFiles
        .where((f) => _selectedFilePaths.contains(f.path))
        .toList();
    if (targetFile != null && !selectedFiles.any((f) => f.path == targetFile.path)) {
      selectedFiles.add(targetFile);
    }
    if (selectedFiles.isEmpty) return;

    final activeFile = targetFile ?? selectedFiles.first;
    PdfTabManager.instance.openMultipleTabs(selectedFiles, activePath: activeFile.path);
    _exitSelectionMode();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(file: activeFile),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _shareSelectedFiles() async {
    final filesToShare = _allFiles
        .where((f) => _selectedFilePaths.contains(f.path))
        .map((f) => XFile(f.path))
        .toList();
    if (filesToShare.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: filesToShare,
          text: '${filesToShare.length} PDF files',
        ),
      );
    } catch (_) {}
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
      for (final path in _selectedFilePaths.toList()) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
          await _scannerService.removeImportedFilePath(path);
          PdfThumbnailService.instance.invalidate(path);
          PdfTabManager.instance.closeTabByPath(path);
        } catch (_) {}
      }
      _clipboardFiles.removeWhere((item) => _selectedFilePaths.contains(item.path));
      if (_clipboardFiles.isEmpty) {
        _isCutMode = false;
      }
      _exitSelectionMode();
      await _startScan();
    }
  }

  void _showFileContextMenu(PdfFileInfo file) {
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
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
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
                    _selectedFilePaths.length > 1
                        ? 'Open Reader (${_selectedFilePaths.length})'
                        : 'Open Reader',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openSelectedFilesInReader(file);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline_rounded),
                  title: const Text('Rename'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _promptRenameFile(file);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: const Text('Open with External App'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openExternal(file);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: Text(
                    _selectedFilePaths.length > 1
                        ? 'Share Selected (${_selectedFilePaths.length})'
                        : 'Share',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (_selectedFilePaths.length > 1) {
                      _shareSelectedFiles();
                    } else {
                      _shareFile(file);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('File Info'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showFileDetails(file);
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

  void _setFolderSort(FolderSortType type) {
    setState(() {
      _folderSortType = type;
    });
    _scannerService.setFolderSort(type.name);
  }

  void _setFileSort(SortType type) {
    setState(() {
      _sortType = type;
      _applyFilterAndSort();
    });
    _scannerService.setFileSort(type.name);
  }

  void _toggleFolderCollapse(String folderPath) {
    setState(() {
      final willCollapse = !_collapsedFolders.contains(folderPath);
      if (willCollapse) {
        _collapsedFolders.add(folderPath);
      } else {
        _collapsedFolders.remove(folderPath);
      }
      _scannerService.setFolderCollapsed(folderPath, willCollapse);
    });
  }

  void _toggleAllFolders(List<String> allFolders) {
    if (allFolders.isEmpty) return;
    final allCollapsed = allFolders.every((f) => _collapsedFolders.contains(f));
    setState(() {
      if (allCollapsed) {
        _collapsedFolders.removeAll(allFolders);
        _scannerService.setAllFoldersCollapsed(allFolders, false);
      } else {
        _collapsedFolders.addAll(allFolders);
        _scannerService.setAllFoldersCollapsed(allFolders, true);
      }
    });
  }

  Widget _buildSortChip<T>({
    required T current,
    required T target,
    required String label,
    required IconData icon,
    required ValueChanged<T> onSelected,
    required ThemeData theme,
  }) {
    final isSelected = current == target;
    return ChoiceChip(
      selected: isSelected,
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
      ),
      selectedColor: theme.colorScheme.primary,
      onSelected: (_) => onSelected(target),
    );
  }

  void _showSortOptionsSheet() {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.tune_rounded, color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Sort Options',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Folder Sorting Header
                    Row(
                      children: [
                        Icon(Icons.folder_rounded, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'FOLDER SORTING',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildSortChip<FolderSortType>(
                          current: _folderSortType,
                          target: FolderSortType.nameAsc,
                          label: 'Name: A to Z',
                          icon: Icons.sort_by_alpha_rounded,
                          onSelected: (val) {
                            _setFolderSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                        _buildSortChip<FolderSortType>(
                          current: _folderSortType,
                          target: FolderSortType.nameDesc,
                          label: 'Name: Z to A',
                          icon: Icons.sort_by_alpha_rounded,
                          onSelected: (val) {
                            _setFolderSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                        _buildSortChip<FolderSortType>(
                          current: _folderSortType,
                          target: FolderSortType.pathAsc,
                          label: 'Path: A to Z',
                          icon: Icons.folder_open_rounded,
                          onSelected: (val) {
                            _setFolderSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                        _buildSortChip<FolderSortType>(
                          current: _folderSortType,
                          target: FolderSortType.pathDesc,
                          label: 'Path: Z to A',
                          icon: Icons.folder_open_rounded,
                          onSelected: (val) {
                            _setFolderSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                        _buildSortChip<FolderSortType>(
                          current: _folderSortType,
                          target: FolderSortType.fileCountDesc,
                          label: 'Files: Most First',
                          icon: Icons.format_list_numbered_rounded,
                          onSelected: (val) {
                            _setFolderSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                        _buildSortChip<FolderSortType>(
                          current: _folderSortType,
                          target: FolderSortType.fileCountAsc,
                          label: 'Files: Fewest First',
                          icon: Icons.format_list_numbered_rounded,
                          onSelected: (val) {
                            _setFolderSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                        _buildSortChip<FolderSortType>(
                          current: _folderSortType,
                          target: FolderSortType.dateDesc,
                          label: 'Date: Newest First',
                          icon: Icons.calendar_today_rounded,
                          onSelected: (val) {
                            _setFolderSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                        _buildSortChip<FolderSortType>(
                          current: _folderSortType,
                          target: FolderSortType.dateAsc,
                          label: 'Date: Oldest First',
                          icon: Icons.history_rounded,
                          onSelected: (val) {
                            _setFolderSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // File Sorting Header
                    Row(
                      children: [
                        Icon(Icons.description_rounded, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'FILE SORTING',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildSortChip<SortType>(
                          current: _sortType,
                          target: SortType.dateDesc,
                          label: 'Date: Newest First',
                          icon: Icons.calendar_today_rounded,
                          onSelected: (val) {
                            _setFileSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                        _buildSortChip<SortType>(
                          current: _sortType,
                          target: SortType.dateAsc,
                          label: 'Date: Oldest First',
                          icon: Icons.history_rounded,
                          onSelected: (val) {
                            _setFileSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                        _buildSortChip<SortType>(
                          current: _sortType,
                          target: SortType.nameAsc,
                          label: 'Name: A to Z',
                          icon: Icons.sort_by_alpha_rounded,
                          onSelected: (val) {
                            _setFileSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                        _buildSortChip<SortType>(
                          current: _sortType,
                          target: SortType.nameDesc,
                          label: 'Name: Z to A',
                          icon: Icons.sort_by_alpha_rounded,
                          onSelected: (val) {
                            _setFileSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                        _buildSortChip<SortType>(
                          current: _sortType,
                          target: SortType.sizeDesc,
                          label: 'Size: Largest First',
                          icon: Icons.storage_rounded,
                          onSelected: (val) {
                            _setFileSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                        _buildSortChip<SortType>(
                          current: _sortType,
                          target: SortType.sizeAsc,
                          label: 'Size: Smallest First',
                          icon: Icons.data_usage_rounded,
                          onSelected: (val) {
                            _setFileSort(val);
                            setSheetState(() {});
                          },
                          theme: theme,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_isSelectionMode && !_isSearching,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          _exitSelectionMode();
        } else if (_isSearching) {
          setState(() {
            _isSearching = false;
            _searchController.clear();
            _applyFilterAndSort();
          });
        }
      },
      child: Scaffold(
        appBar: _isSelectionMode
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
                onChanged: (val) {
                  setState(() {
                    _applyFilterAndSort();
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
                setState(() {
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
                setState(() {
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
              setState(() {
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
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Permission Alert Banner (if not granted)
              if (!_hasPermission)
                MaterialBanner(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  backgroundColor: theme.colorScheme.errorContainer,
                  leading: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
                  content: Text(
                    'Storage permission not granted. Some PDF files may not be discovered automatically.',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 13),
                  ),
                  actions: [
                    TextButton(
                      onPressed: _importFiles,
                      child: const Text('Pick Files'),
                    ),
                    FilledButton(
                      onPressed: _requestPermissionManually,
                      child: const Text('Grant Permission'),
                    ),
                  ],
                ),

              // Top Rounded Rectangle for Open Tabs Count (User Request 3)
              if (PdfTabManager.instance.tabCount > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Material(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        final active = PdfTabManager.instance.activeFile;
                        if (active != null) {
                          _openPdfViewer(active);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.tab_rounded,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        PdfTabManager.instance.tabCount == 1
                                            ? '1 Open Tab'
                                            : '${PdfTabManager.instance.tabCount} Open Tabs',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: theme.colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          'ACTIVE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    PdfTabManager.instance.openTabs.map((t) => t.name).join(' • '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: () {
                                final active = PdfTabManager.instance.activeFile;
                                if (active != null) {
                                  _openPdfViewer(active);
                                }
                              },
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              ),
                              child: const Text('Resume Reading', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Main Content
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _startScan,
                  child: _buildBody(theme),
                ),
              ),
            ],
          ),

          // Floating Progress Pill at bottom during scanning / refresh
          if (_isLoading && _allFiles.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 84,
              child: Center(
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(24),
                  color: theme.colorScheme.surfaceContainerHighest,
                  shadowColor: Colors.black38,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            _scanStatusText.isNotEmpty
                                ? _scanStatusText
                                : 'Refreshing library...',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddOptions,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add PDF'),
            ),
      ),
    );
  }

  List<MapEntry<String, List<PdfFileInfo>>> get _sortedGroupedEntries {
    final Map<String, List<PdfFileInfo>> groups = {};
    for (final file in _filteredFiles) {
      final folder = file.parentDirectoryPath.isNotEmpty
          ? file.parentDirectoryPath
          : 'Root Directory';
      groups.putIfAbsent(folder, () => []).add(file);
    }

    final entries = groups.entries.toList();

    String getFolderName(String folderPath) {
      final segments = folderPath.split(Platform.pathSeparator).where((s) => s.isNotEmpty).toList();
      return segments.isNotEmpty ? segments.last.toLowerCase() : folderPath.toLowerCase();
    }

    DateTime getLatestDate(List<PdfFileInfo> files) {
      if (files.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
      return files.map((f) => f.lastModified).reduce((a, b) => a.isAfter(b) ? a : b);
    }

    switch (_folderSortType) {
      case FolderSortType.nameAsc:
        entries.sort((a, b) => getFolderName(a.key).compareTo(getFolderName(b.key)));
        break;
      case FolderSortType.nameDesc:
        entries.sort((a, b) => getFolderName(b.key).compareTo(getFolderName(a.key)));
        break;
      case FolderSortType.pathAsc:
        entries.sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
        break;
      case FolderSortType.pathDesc:
        entries.sort((a, b) => b.key.toLowerCase().compareTo(a.key.toLowerCase()));
        break;
      case FolderSortType.fileCountDesc:
        entries.sort((a, b) {
          final cmp = b.value.length.compareTo(a.value.length);
          return cmp != 0 ? cmp : getFolderName(a.key).compareTo(getFolderName(b.key));
        });
        break;
      case FolderSortType.fileCountAsc:
        entries.sort((a, b) {
          final cmp = a.value.length.compareTo(b.value.length);
          return cmp != 0 ? cmp : getFolderName(a.key).compareTo(getFolderName(b.key));
        });
        break;
      case FolderSortType.dateDesc:
        entries.sort((a, b) {
          final cmp = getLatestDate(b.value).compareTo(getLatestDate(a.value));
          return cmp != 0 ? cmp : getFolderName(a.key).compareTo(getFolderName(b.key));
        });
        break;
      case FolderSortType.dateAsc:
        entries.sort((a, b) {
          final cmp = getLatestDate(a.value).compareTo(getLatestDate(b.value));
          return cmp != 0 ? cmp : getFolderName(a.key).compareTo(getFolderName(b.key));
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
    final segments = folderPath.split(Platform.pathSeparator).where((s) => s.isNotEmpty).toList();
    final folderName = segments.isNotEmpty ? segments.last : folderPath;

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
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (groupedEntries.isNotEmpty)
          SliverToBoxAdapter(
            child: _buildFoldersHeaderBar(groupedEntries, theme),
          ),
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
                        isOpen: PdfTabManager.instance.isOpen(file.path),
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
                        isOpen: PdfTabManager.instance.isOpen(file.path),
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

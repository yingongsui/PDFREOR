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

  final Set<String> _collapsedFolders = {};
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  PdfFileInfo? _clipboardFile;
  bool _isCutMode = false;

  @override
  void initState() {
    super.initState();
    PdfTabManager.instance.init();
    PdfTabManager.instance.addListener(_onTabStateChanged);
    _checkPermissionAndScan();
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
    } catch (e) {
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

  void _copyFile(PdfFileInfo file) {
    setState(() {
      _clipboardFile = file;
      _isCutMode = false;
    });
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "${file.name}" to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _cutFile(PdfFileInfo file) {
    setState(() {
      _clipboardFile = file;
      _isCutMode = true;
    });
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cut "${file.name}". Tap Paste to move here.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pasteFile({PdfFileInfo? targetFile}) async {
    if (_clipboardFile == null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clipboard is empty. Copy or Cut a file first.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final sourcePath = _clipboardFile!.path;
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Source file no longer exists.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _clipboardFile = null;
        _isCutMode = false;
      });
      return;
    }

    final targetDir = targetFile != null
        ? File(targetFile.path).parent
        : sourceFile.parent;

    final baseName = p.basenameWithoutExtension(sourcePath);
    final ext = p.extension(sourcePath);

    try {
      if (_isCutMode) {
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
        }
        setState(() {
          _clipboardFile = null;
          _isCutMode = false;
        });
        await _startScan();
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File moved successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        String destPath = p.join(targetDir.path, '$baseName (Copy)$ext');
        int counter = 2;
        while (await File(destPath).exists()) {
          destPath = p.join(targetDir.path, '$baseName (Copy $counter)$ext');
          counter++;
        }
        await sourceFile.copy(destPath);
        await _startScan();
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Created copy: "${p.basename(destPath)}"'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Paste operation failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteFile(PdfFileInfo file) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Delete File?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${file.name}"? This file will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final f = File(file.path);
      if (await f.exists()) {
        await f.delete();
      }
      PdfTabManager.instance.closeTabByPath(file.path);
      PdfThumbnailService.instance.invalidate(file.path);
      setState(() {
        _allFiles.removeWhere((item) => item.path == file.path);
        _applyFilterAndSort();
        if (_clipboardFile?.path == file.path) {
          _clipboardFile = null;
          _isCutMode = false;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${file.name}"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  PopupMenuItem<SortType> _buildSortMenuItem(SortType type, IconData icon, String text) {
    final isSelected = _sortType == type;
    final theme = Theme.of(context);
    return PopupMenuItem<SortType>(
      value: type,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? theme.colorScheme.primary : null,
              ),
            ),
          ),
          if (isSelected)
            Icon(Icons.check_rounded, size: 18, color: theme.colorScheme.primary),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
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
          PopupMenuButton<SortType>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort Options',
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            initialValue: _sortType,
            onSelected: (val) {
              setState(() {
                _sortType = val;
                _applyFilterAndSort();
              });
            },
            itemBuilder: (context) => [
              _buildSortMenuItem(SortType.dateDesc, Icons.calendar_today_rounded, 'Date: Newest First'),
              _buildSortMenuItem(SortType.dateAsc, Icons.history_rounded, 'Date: Oldest First'),
              const PopupMenuDivider(),
              _buildSortMenuItem(SortType.nameAsc, Icons.sort_by_alpha_rounded, 'Name: A to Z'),
              _buildSortMenuItem(SortType.nameDesc, Icons.sort_by_alpha_rounded, 'Name: Z to A'),
              const PopupMenuDivider(),
              _buildSortMenuItem(SortType.sizeDesc, Icons.storage_rounded, 'Size: Largest First'),
              _buildSortMenuItem(SortType.sizeAsc, Icons.data_usage_rounded, 'Size: Smallest First'),
            ],
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importFiles,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add PDF'),
      ),
    );
  }

  Map<String, List<PdfFileInfo>> get _groupedFiles {
    final Map<String, List<PdfFileInfo>> groups = {};
    for (final file in _filteredFiles) {
      final folder = file.parentDirectoryPath.isNotEmpty
          ? file.parentDirectoryPath
          : 'Root Directory';
      groups.putIfAbsent(folder, () => []).add(file);
    }
    return groups;
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
          onTap: () {
            setState(() {
              if (isCollapsed) {
                _collapsedFolders.remove(folderPath);
              } else {
                _collapsedFolders.add(folderPath);
              }
            });
          },
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

    final grouped = _groupedFiles;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        for (final entry in grouped.entries) ...[
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
                        onTap: () => _openPdfViewer(file),
                        onLongPress: () => _promptRenameFile(file),
                        onRename: () => _promptRenameFile(file),
                        onOpenExternal: () => _openExternal(file),
                        onShare: () => _shareFile(file),
                        onShowDetails: () => _showFileDetails(file),
                        onDelete: () => _deleteFile(file),
                        onCopy: () => _copyFile(file),
                        onCut: () => _cutFile(file),
                        onPaste: () => _pasteFile(targetFile: file),
                        canPaste: _clipboardFile != null,
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
                        onTap: () => _openPdfViewer(file),
                        onLongPress: () => _promptRenameFile(file),
                        onRename: () => _promptRenameFile(file),
                        onOpenExternal: () => _openExternal(file),
                        onShare: () => _shareFile(file),
                        onShowDetails: () => _showFileDetails(file),
                        onDelete: () => _deleteFile(file),
                        onCopy: () => _copyFile(file),
                        onCut: () => _cutFile(file),
                        onPaste: () => _pasteFile(targetFile: file),
                        canPaste: _clipboardFile != null,
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

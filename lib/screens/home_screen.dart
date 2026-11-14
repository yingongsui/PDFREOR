import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../models/pdf_file_info.dart';
import '../services/pdf_scanner_service.dart';
import '../services/pdf_tab_manager.dart';
import '../services/pdf_thumbnail_service.dart';
import '../services/reading_progress_service.dart';
import '../widgets/pdf_list_tile.dart';
import '../widgets/pdf_thumbnail_card.dart';
import 'home/home_dialogs.dart';
import 'home/home_models.dart';
import 'home/home_sort_sheet.dart';
import 'pdf_viewer_screen.dart';
import 'settings_screen.dart';

export 'home/home_models.dart';

part 'home/home_screen_actions.dart';
part 'home/home_screen_appbar.dart';
part 'home/home_screen_views.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _intentChannel = MethodChannel('com.yin.pdfreor/intent');

  final PdfScannerService _scannerService = PdfScannerService.instance;

  List<PdfFileInfo> _allFiles = [];
  List<PdfFileInfo> _filteredFiles = [];
  List<MapEntry<String, List<PdfFileInfo>>>? _cachedGroupedEntries;

  bool _isLoading = false;
  bool _hasPermission = true;
  String _scanStatusText = '';
  bool _isViewerRouteOpen = false;

  PdfViewMode _viewMode = PdfViewMode.thumbnail;
  SortType _sortType = SortType.dateDesc;
  FolderSortType _folderSortType = FolderSortType.nameAsc;

  final Set<String> _collapsedFolders = {};
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  List<PdfFileInfo> _clipboardFiles = [];
  bool _isCutMode = false;
  bool _isSelectionMode = false;
  final Set<String> _selectedFilePaths = {};

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    PdfTabManager.instance.addListener(_onTabStateChanged);
    _intentChannel.setMethodCallHandler(_handleIntentChannelCall);
    _intentChannel.invokeMethod<String>('consumeInitialPdfPath').then((path) {
      if (path != null && path.isNotEmpty && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openExternalIntentPdf(path);
        });
      }
    }).catchError((_) {});
    _checkPermissionAndScan();
  }

  Future<void> _handleIntentChannelCall(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'onOpenExternalPdf') {
      final path = call.arguments as String?;
      if (path != null && path.isNotEmpty) {
        _openExternalIntentPdf(path);
      }
    }
  }

  Future<void> _openExternalIntentPdf(String path) async {
    final ioFile = File(path);
    if (!await ioFile.exists()) return;
    try {
      final info = PdfFileInfo.fromFile(ioFile);
      await _scannerService.addImportedFilePaths([path]);
      if (mounted) {
        setState(() {
          if (!_allFiles.any((f) => f.path == path)) {
            _allFiles.insert(0, info);
          }
          _applyFilterAndSort();
        });
      }
      if (_isViewerRouteOpen) {
        PdfTabManager.instance.openTab(info);
      } else if (mounted) {
        _openPdfViewer(info);
      }
    } catch (_) {}
  }

  Future<void> _loadPreferences() async {
    try {
      final collapsed = await _scannerService.getCollapsedFolders();
      final folderSortStr = await _scannerService.getFolderSort();
      final fileSortStr = await _scannerService.getFileSort();

      final fSort = FolderSortType.values.asNameMap()[folderSortStr] ?? FolderSortType.nameAsc;
      final sSort = SortType.values.asNameMap()[fileSortStr] ?? SortType.dateDesc;

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
    if (!mounted || _isViewerRouteOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isViewerRouteOpen) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _intentChannel.setMethodCallHandler(null);
    PdfTabManager.instance.removeListener(_onTabStateChanged);
    _searchController.dispose();
    super.dispose();
  }


  void _refresh([VoidCallback? fn]) {
    if (mounted) {
      setState(fn ?? () {});
    }
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
        appBar: _buildHomeAppBar(theme),
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

              // Open Tabs Banner
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
                child: Column(
                  children: [
                    if (_sortedGroupedEntries.isNotEmpty)
                      _buildFoldersHeaderBar(_sortedGroupedEntries, theme),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _startScan,
                        child: _buildBody(theme),
                      ),
                    ),
                  ],
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
                            _scanStatusText,
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

}

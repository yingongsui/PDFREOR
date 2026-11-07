import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import '../controllers/drawing_controller.dart';
import '../models/editor_models.dart';
import '../models/pdf_file_info.dart';
import '../services/editor_settings_service.dart';
import '../services/pdf_export_service.dart';
import '../services/pdf_system_font_service.dart';
import '../services/pdf_tab_manager.dart';
import '../services/pdf_thumbnail_service.dart';
import '../services/reading_progress_service.dart';
import '../widgets/pass_through_stack.dart';
import '../widgets/pdf_annotation_property_bar.dart';
import '../widgets/pdf_editor_canvas.dart';
import '../widgets/pdf_floating_toolbar.dart';
import '../widgets/pdf_page_manager_dialog.dart';
import '../widgets/pdf_thumbnails_sidebar.dart';

class PdfViewerScreen extends StatefulWidget {
  final PdfFileInfo? file;

  const PdfViewerScreen({super.key, this.file});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> with WidgetsBindingObserver {
  static const _stylusChannel = MethodChannel('com.yin.pdfreor/stylus');
  static const int _maxMountedCleanTabs = 3;

  final Map<String, GlobalKey<PdfTabContentState>> _tabKeys = {};
  final LinkedHashSet<String> _activatedTabPaths = LinkedHashSet<String>();
  final ValueNotifier<(int, int)> _pageInfoNotifier = ValueNotifier<(int, int)>((1, 1));

  bool _isStylusConnectedCache = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.file != null) {
      PdfTabManager.instance.openTab(widget.file!);
    }
    _syncActivePageInfo();
    PdfTabManager.instance.addListener(_onTabManagerChanged);
    _stylusChannel.setMethodCallHandler(_handleStylusPlatformCall);
    _stylusChannel.invokeMethod<bool>('isStylusConnected').then((connected) {
      if (connected == true && mounted) {
        _isStylusConnectedCache = true;
        _activeTabState?.notifyStylusConnected();
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ReadingProgressService.instance.flush().ignore();
    _stylusChannel.setMethodCallHandler(null);
    PdfTabManager.instance.removeListener(_onTabManagerChanged);
    _pageInfoNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ReadingProgressService.instance.flush().ignore();
    }
  }

  PdfTabContentState? get _activeTabState {
    final active = PdfTabManager.instance.activeFile;
    if (active == null) return null;
    return _tabKeys[active.path]?.currentState;
  }

  Future<void> _handleStylusPlatformCall(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'onStylusConnected') {
      _isStylusConnectedCache = true;
    }
    await _activeTabState?.handleStylusPlatformCall(call);
  }

  void _syncActivePageInfo() {
    final active = PdfTabManager.instance.activeFile;
    if (active != null) {
      final state = _tabKeys[active.path]?.currentState;
      if (state != null) {
        _pageInfoNotifier.value = (state.currentPage, state.pagesCount);
        if (_isStylusConnectedCache) {
          state.notifyStylusConnected();
        }
      } else {
        final remembered = ReadingProgressService.instance.getLastPage(active.path);
        _pageInfoNotifier.value = (remembered, math.max(1, remembered));
      }
    }
  }

  void _onTabManagerChanged() {
    if (mounted) {
      _syncActivePageInfo();
      setState(() {});
    }
  }

  void _onPageInfoChanged(int current, int total) {
    if (!mounted) return;
    final next = (current, total);
    if (_pageInfoNotifier.value != next) {
      _pageInfoNotifier.value = next;
    }
  }

  void _openThumbnailsSidebar() {
    final activeFile = PdfTabManager.instance.activeFile;
    if (activeFile == null) return;
    final activeState = _tabKeys[activeFile.path]?.currentState;
    final currentInfo = _pageInfoNotifier.value;
    final totalPages = activeState?.pagesCount ?? currentInfo.$2;
    final currentPage = activeState?.currentPage ?? currentInfo.$1;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: PdfThumbnailsSidebar(
              file: activeFile,
              totalPages: totalPages,
              currentPage: currentPage,
              onPageSelected: (pageNumber) {
                activeState?.jumpToPage(pageNumber);
                _pageInfoNotifier.value = (pageNumber, totalPages);
                Navigator.of(dialogContext).pop();
              },
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(anim1),
          child: child,
        );
      },
    );
  }

  Future<void> _closeTab(int index) async {
    final tabs = PdfTabManager.instance.openTabs;
    if (index < 0 || index >= tabs.length) return;
    final file = tabs[index];
    final tabState = _tabKeys[file.path]?.currentState;

    if (tabState != null && tabState.hasUnsavedChanges) {
      final shouldClose = await tabState.promptSaveIfDirty();
      if (!shouldClose) return;
    }

    _tabKeys.remove(file.path);
    _activatedTabPaths.remove(file.path);
    PdfTabManager.instance.closeTab(index);

    if (PdfTabManager.instance.tabCount == 0 && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleBack() async {
    final active = PdfTabManager.instance.activeFile;
    if (active != null) {
      final activeState = _tabKeys[active.path]?.currentState;
      if (activeState != null && activeState.handleBackPress()) {
        return;
      }
    }

    // Check all open tabs for unsaved changes before exiting to library
    for (int i = 0; i < PdfTabManager.instance.openTabs.length; i++) {
      final tab = PdfTabManager.instance.openTabs[i];
      final state = _tabKeys[tab.path]?.currentState;
      if (state != null && state.hasUnsavedChanges) {
        if (i != PdfTabManager.instance.activeIndex) {
          PdfTabManager.instance.setActiveIndex(i);
        }
        final proceed = await state.promptSaveIfDirty();
        if (!proceed) {
          return;
        }
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = PdfTabManager.instance.openTabs;
    final activeIdx = PdfTabManager.instance.activeIndex;
    final activeFile = PdfTabManager.instance.activeFile;

    if (activeFile != null) {
      _activatedTabPaths.remove(activeFile.path);
      _activatedTabPaths.add(activeFile.path);
    }
    final currentPaths = tabs.map((t) => t.path).toSet();
    _tabKeys.removeWhere((k, _) => !currentPaths.contains(k));
    _activatedTabPaths.removeWhere((p) => !currentPaths.contains(p));

    // Evict least-recently-used clean background tab viewers to cap native bitmap memory
    if (_activatedTabPaths.length > _maxMountedCleanTabs) {
      final cleanPaths = _activatedTabPaths.where((p) {
        final isDirty = _tabKeys[p]?.currentState?.hasUnsavedChanges ?? false;
        return !isDirty;
      }).toList();
      int excess = cleanPaths.length - _maxMountedCleanTabs;
      for (final candidate in cleanPaths) {
        if (excess <= 0) break;
        if (candidate == activeFile?.path) continue;
        _activatedTabPaths.remove(candidate);
        _tabKeys.remove(candidate);
        excess--;
      }
    }

    if (tabs.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: Center(child: Text('No tabs open')));
    }

    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to Library',
            onPressed: () => _handleBack(),
          ),
          title: Text(
            activeFile?.name ?? 'PDFREOR',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: PopupMenuButton<int>(
                tooltip: 'Open Documents',
                offset: const Offset(0, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                onSelected: (int selectedIndex) {
                  PdfTabManager.instance.setActiveIndex(selectedIndex);
                },
                itemBuilder: (context) {
                  return [
                    for (int i = 0; i < tabs.length; i++)
                      PopupMenuItem<int>(
                        value: i,
                        child: Row(
                          children: [
                            Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 18,
                              color: (_tabKeys[tabs[i].path]?.currentState?.hasUnsavedChanges ?? false)
                                  ? Colors.red.shade600
                                  : (i == activeIdx
                                      ? const Color(0xFF1E90FF)
                                      : theme.colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                tabs[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: i == activeIdx ? FontWeight.bold : FontWeight.normal,
                                  color: i == activeIdx ? const Color(0xFF1E90FF) : null,
                                ),
                              ),
                            ),
                            if (i == activeIdx) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E90FF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ];
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF1E90FF),
                      width: 1.4,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.tab_rounded,
                        size: 16,
                        color: Color(0xFF1E90FF),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${tabs.length}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E90FF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 12),
              child: InkWell(
                onTap: _openThumbnailsSidebar,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF1E90FF),
                      width: 1.4,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.auto_stories_outlined,
                        size: 16,
                        color: Color(0xFF1E90FF),
                      ),
                      const SizedBox(width: 6),
                      ValueListenableBuilder<(int, int)>(
                        valueListenable: _pageInfoNotifier,
                        builder: (context, info, _) {
                          return Text(
                            '${info.$1} / ${info.$2}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E90FF),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: _buildTabBar(tabs, activeIdx, theme),
          ),
        ),
        body: IndexedStack(
          index: activeIdx.clamp(0, math.max(0, tabs.length - 1)),
          children: [
            for (int i = 0; i < tabs.length; i++)
              _activatedTabPaths.contains(tabs[i].path)
                  ? PdfTabContent(
                      key: _tabKeys.putIfAbsent(tabs[i].path, () => GlobalKey<PdfTabContentState>()),
                      file: tabs[i],
                      initialStylusConnected: _isStylusConnectedCache,
                      onDirtyChanged: () {
                        if (mounted) setState(() {});
                      },
                      onPageInfoChanged: (current, total) {
                        if (i == PdfTabManager.instance.activeIndex) {
                          _onPageInfoChanged(current, total);
                        }
                      },
                    )
                  : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(List<PdfFileInfo> tabs, int activeIdx, ThemeData theme) {
    return Container(
      height: 40,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          children: [
            for (int i = 0; i < tabs.length; i++)
              _buildTabItem(i, tabs[i], i == activeIdx, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, PdfFileInfo file, bool isActive, ThemeData theme) {
    final isDirty = _tabKeys[file.path]?.currentState?.hasUnsavedChanges ?? false;

    return Container(
      margin: const EdgeInsets.only(right: 6),
      child: Material(
        color: isActive
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (!isActive) {
              PdfTabManager.instance.setActiveIndex(index);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive
                    ? theme.colorScheme.primary.withValues(alpha: 0.5)
                    : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 15,
                  color: isDirty
                      ? Colors.red.shade600
                      : (isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      color: isActive
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _closeTab(index),
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.12)
                          : Colors.transparent,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 13,
                      color: isActive
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PdfTabContent extends StatefulWidget {
  final PdfFileInfo file;
  final bool initialStylusConnected;
  final VoidCallback? onDirtyChanged;
  final void Function(int currentPage, int totalPages)? onPageInfoChanged;

  const PdfTabContent({
    super.key,
    required this.file,
    this.initialStylusConnected = false,
    this.onDirtyChanged,
    this.onPageInfoChanged,
  });

  @override
  State<PdfTabContent> createState() => PdfTabContentState();
}

class PdfTabContentState extends State<PdfTabContent> {
  static pdfrx.PdfPageLayout _layoutVerticalPages(
    List<pdfrx.PdfPage> pages,
    pdfrx.PdfViewerParams params,
  ) {
    if (pages.isEmpty) {
      return pdfrx.PdfPageLayout(
        pageLayouts: const [],
        documentSize: Size.zero,
      );
    }
    double maxWidth = 0.0;
    for (final p in pages) {
      if (p.width > maxWidth) {
        maxWidth = p.width;
      }
    }
    final gap = math.max(1.0, maxWidth * 0.0065);
    final layouts = <Rect>[];
    double y = 0.0;
    for (int i = 0; i < pages.length; i++) {
      final p = pages[i];
      final left = (maxWidth - p.width) / 2.0;
      layouts.add(Rect.fromLTWH(left, y, p.width, p.height));
      y += p.height;
      if (i < pages.length - 1) {
        y += gap;
      }
    }
    return pdfrx.PdfPageLayout(
      pageLayouts: layouts,
      documentSize: Size(maxWidth, y),
    );
  }

  /// Computes the initial top-left document offset and zoom level so the viewer
  /// opens immediately at [savedZoom] (if present) or fits [pageLayout]'s width,
  /// horizontally centered on [pageLayout].
  @visibleForTesting
  static ({Offset documentOffset, double zoom}) computeInitialViewportTarget({
    required Rect pageLayout,
    required double viewWidth,
    required double? savedZoom,
    double minScale = 0.2,
    double maxScale = 8.0,
  }) {
    final double targetZoom;
    if (savedZoom != null && savedZoom >= minScale) {
      targetZoom = savedZoom.clamp(minScale, maxScale);
    } else {
      final rawFitPageWidth = pageLayout.width > 0 ? viewWidth / pageLayout.width : 1.0;
      targetZoom = rawFitPageWidth.clamp(minScale, maxScale);
    }
    final viewportDocWidth = viewWidth / targetZoom;
    final dx = pageLayout.center.dx - viewportDocWidth / 2.0;
    return (
      documentOffset: Offset(dx, pageLayout.top),
      zoom: targetZoom,
    );
  }

  static Widget _suppressBuiltInContextMenu(
    BuildContext context,
    pdfrx.PdfViewerContextMenuBuilderParams params,
  ) {
    return const SizedBox.shrink();
  }

  static List<Rect> _mergeLineRects(List<Rect> rawRects) {
    if (rawRects.length <= 1) return rawRects;
    final merged = <Rect>[];
    Rect current = rawRects.first;
    for (int i = 1; i < rawRects.length; i++) {
      final next = rawRects[i];
      final minH = math.min(current.height, next.height);
      final maxH = math.max(current.height, next.height);
      final sameLine = minH > 0 &&
          (current.center.dy - next.center.dy).abs() <= minH * 0.45 &&
          next.left >= current.left - maxH * 0.5 &&
          (next.left - current.right) <= maxH * 0.85;
      if (sameLine) {
        current = current.expandToInclude(next);
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);
    return merged;
  }

  late final pdfrx.PdfViewerController _pdfViewerController;
  late final TransformationController _transformationController;
  late DrawingController _drawingController;
  late File _pdfFile;
  late pdfrx.PdfDocumentRefFile _documentRef;
  int _reloadGeneration = 0;

  double? _baseNormalizedWidth;
  double _docToCanvasScale = 1.0;

  static const _stylusChannel = MethodChannel('com.yin.pdfreor/stylus');

  bool _isLoading = true;
  String? _errorMessage;
  Timer? _loadingWatchdogTimer;
  Uint8List? _originalBaseBytes;
  bool _isSaving = false;

  bool _lastCanUndo = false;
  bool _lastNotifiedDirty = false;

  void _rebuildDocumentRef() {
    _documentRef = pdfrx.PdfDocumentRefFile(
      _pdfFile.path,
      useProgressiveLoading: false,
      key: pdfrx.PdfDocumentRefKey(_pdfFile.path, [_reloadGeneration]),
    );
  }

  void _startLoadingWatchdog() {
    _loadingWatchdogTimer?.cancel();
    _loadingWatchdogTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  int _initialPageNumber = 1;
  bool _isDocumentLoaded = false;
  int _currentPage = 1;
  int _pagesCount = 1;

  int get currentPage => _currentPage;
  int get pagesCount => _pagesCount;

  void jumpToPage(int pageNumber) {
    if (pageNumber >= 1 && pageNumber <= _pagesCount) {
      if (_pdfViewerController.isReady) {
        _pdfViewerController.goToPage(
          pageNumber: pageNumber,
          anchor: pdfrx.PdfPageAnchor.top,
          duration: Duration.zero,
        );
      }
      setState(() {
        _currentPage = pageNumber;
      });
      ReadingProgressService.instance.saveLastPage(widget.file.path, _currentPage);
      widget.onPageInfoChanged?.call(_currentPage, _pagesCount);
    }
  }

  // Editor states
  EditorTool _activeTool = EditorTool.select;
  bool _isHardwareButtonPressed = false;
  bool _isPointerButtonPressed = false;
  String? _editingTextBoxId;
  ShapeType? _oneShotShape;
  bool _hasActiveTextSelection = false;

  String? _selectedTextAnnotationId;
  String? _selectedShapeId;
  String? _selectedStrokeId;
  final List<Rect> _pageDocBounds = [];
  final ValueNotifier<Rect?> _textSelectionLocalRectNotifier = ValueNotifier<Rect?>(null);
  Rect? _selectedUnionPdfrxDocRect;
  Map<int, List<Rect>> _selectedPageDocRects = const {};
  String? _selectedText;
  bool _isDraggingSelectionHandle = false;
  int _selectionSyncSerial = 0;
  double _lastReportedZoom = -1.0;

  bool get _isEraserActive => _isHardwareButtonPressed || _isPointerButtonPressed;

  bool get _shouldEnableTextSelection {
    if (_oneShotShape != null) return false;
    if (_stylusOnlyMode || _isStylusDetected) return true;
    return _activeTool == EditorTool.select;
  }

  bool get _shouldAllowViewerPan {
    if (_oneShotShape != null) return false;
    if (_stylusOnlyMode) return true;
    return _activeTool == EditorTool.select;
  }

  bool get _hasUnsavedChanges {
    final hasPageChanges = _deletedZeroIndexedPages.isNotEmpty || _addedPagesCount > 0;
    if (hasPageChanges) return true;
    return _drawingController.hasUnsavedChanges;
  }

  ShapeType _activeShape = ShapeType.rectangle;
  Color _activeColor = const Color(0xFF212121);
  Color _highlightColor = const Color(0xFFFFEB3B);
  Color _underlineColor = const Color(0xFFF44336);
  double _activeStrokeWidth = 3.0;
  double _activeFontSize = 16.0;
  Offset _toolbarPosition = const Offset(12, 100);
  bool _toolbarCollapsed = false;
  bool _isStylusDetected = false;
  bool _stylusOnlyMode = false;
  AppFontFamily _textBoxFont = AppFontFamily.sansSerif;

  void _applyEditorSettings(EditorSettings s) {
    _activeColor = s.activeColor;
    _highlightColor = s.highlightColor;
    _underlineColor = s.underlineColor;
    _activeStrokeWidth = s.activeStrokeWidth;
    _activeShape = s.activeShape;
    _toolbarPosition = Offset(s.toolbarPositionX, s.toolbarPositionY);
    _toolbarCollapsed = s.toolbarCollapsed;
    _textBoxFont = s.textBoxFont;
  }

  void _onExternalSettingsChanged() {
    if (!mounted) return;
    final s = EditorSettingsService.settingsNotifier.value;
    if (_textBoxFont != s.textBoxFont ||
        _activeColor != s.activeColor ||
        _highlightColor != s.highlightColor ||
        _underlineColor != s.underlineColor ||
        _activeStrokeWidth != s.activeStrokeWidth ||
        _activeShape != s.activeShape ||
        _toolbarCollapsed != s.toolbarCollapsed) {
      setState(() {
        _applyEditorSettings(s);
      });
    } else {
      _toolbarPosition = Offset(s.toolbarPositionX, s.toolbarPositionY);
    }
  }

  void _saveSettings() {
    EditorSettingsService.saveSettings(
      EditorSettingsService.settingsNotifier.value.copyWith(
        activeColor: _activeColor,
        highlightColor: _highlightColor,
        underlineColor: _underlineColor,
        activeStrokeWidth: _activeStrokeWidth,
        activeShape: _activeShape,
        toolbarPositionX: _toolbarPosition.dx,
        toolbarPositionY: _toolbarPosition.dy,
        toolbarCollapsed: _toolbarCollapsed,
        textBoxFont: _textBoxFont,
      ),
    );
  }

  // Pending page manager operations
  List<int> _deletedZeroIndexedPages = [];
  int _addedPagesCount = 0;
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _pdfFile = File(widget.file.path);
    _rebuildDocumentRef();
    if (!_pdfFile.existsSync()) {
      _errorMessage = 'File does not exist: ${widget.file.path}';
      _isLoading = false;
    } else {
      _startLoadingWatchdog();
    }
    _pdfViewerController = pdfrx.PdfViewerController();
    _transformationController = TransformationController();
    _pdfViewerController.addListener(_onPdfMatrixChanged);
    _initialPageNumber = ReadingProgressService.instance.getLastPage(widget.file.path);
    _currentPage = _initialPageNumber;
    _pagesCount = math.max(1, _initialPageNumber);
    _drawingController = DrawingController();
    _drawingController.addListener(_onDrawingControllerChanged);
    EditorSettingsService.settingsNotifier.addListener(_onExternalSettingsChanged);

    if (widget.initialStylusConnected) {
      _isStylusDetected = true;
      _stylusOnlyMode = true;
      _activeTool = EditorTool.pen;
    }

    EditorSettingsService.loadSettings().then((s) {
      if (mounted) {
        setState(() {
          _applyEditorSettings(s);
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant PdfTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _pdfFile = File(widget.file.path);
      _reloadGeneration++;
      _baseNormalizedWidth = null;
      _rebuildDocumentRef();
    }
    if (!oldWidget.initialStylusConnected && widget.initialStylusConnected) {
      _onStylusDetected();
    }
  }

  @override
  void dispose() {
    ReadingProgressService.instance.flush().ignore();
    _originalBaseBytes = null;
    _loadingWatchdogTimer?.cancel();
    EditorSettingsService.settingsNotifier.removeListener(_onExternalSettingsChanged);
    _pdfViewerController.removeListener(_onPdfMatrixChanged);
    _textSelectionLocalRectNotifier.dispose();
    _transformationController.dispose();
    _drawingController.removeListener(_onDrawingControllerChanged);
    _drawingController.dispose();
    super.dispose();
  }

  void notifyStylusConnected() {
    if (mounted) {
      _onStylusDetected();
    }
  }

  void _notifyDirtyIfChanged() {
    final dirtyNow = _hasUnsavedChanges;
    if (dirtyNow != _lastNotifiedDirty) {
      _lastNotifiedDirty = dirtyNow;
      widget.onDirtyChanged?.call();
    }
  }

  void _onDrawingControllerChanged() {
    if (!mounted) return;

    final isActivelyDrawingPreview = _drawingController.activeStrokePoints != null ||
        _drawingController.activeShapeStart != null;
    final canUndoNow = _drawingController.canUndo;
    final dirtyNow = _hasUnsavedChanges;

    // During 120-240Hz stylus movement, only _ActiveAnnotationPainter repaints via activeLayerListenable.
    // Skip rebuilding PdfTabContent and PdfViewerScreen unless undo/dirty state changed.
    if (isActivelyDrawingPreview &&
        canUndoNow == _lastCanUndo &&
        dirtyNow == _lastNotifiedDirty) {
      return;
    }

    _lastCanUndo = canUndoNow;
    setState(() {});
    _notifyDirtyIfChanged();
  }

  void _syncTransformationMatrix() {
    if (!_pdfViewerController.isReady) return;
    final k = _docToCanvasScale > 0 ? _docToCanvasScale : 1.0;
    final next = _pdfViewerController.value.multiplied(
      Matrix4.diagonal3Values(k, k, k),
    );
    if (_transformationController.value != next) {
      _transformationController.value = next;
    }
  }

  void _syncDocumentLayoutFromController() {
    if (!_pdfViewerController.isReady) return;
    final layout = _pdfViewerController.layout;
    if (layout.pageLayouts.isEmpty || layout.documentSize.width <= 0) {
      return;
    }
    _baseNormalizedWidth ??= _canvasSize.width > 0 ? _canvasSize.width : 600.0;
    final baseW = _baseNormalizedWidth!;
    final k = layout.documentSize.width / baseW;
    _docToCanvasScale = k > 0 ? k : 1.0;

    _pageDocBounds
      ..clear()
      ..addAll(
        layout.pageLayouts.map(
          (r) => Rect.fromLTRB(
            r.left / _docToCanvasScale,
            r.top / _docToCanvasScale,
            r.right / _docToCanvasScale,
            r.bottom / _docToCanvasScale,
          ),
        ),
      );
    _syncTransformationMatrix();
  }

  Rect? _computeLocalRectFromPdfrxDocRect(Rect pdfrxDocRect) {
    if (!_pdfViewerController.isReady) return null;
    final p1 = _pdfViewerController.documentToLocal(pdfrxDocRect.topLeft);
    final p2 = _pdfViewerController.documentToLocal(pdfrxDocRect.bottomRight);
    final localRect = Rect.fromPoints(p1, p2);
    final viewport = Offset.zero & _canvasSize;
    if (!viewport.isEmpty && !localRect.overlaps(viewport)) {
      return null;
    }
    return localRect;
  }

  void _onPdfMatrixChanged() {
    if (!mounted || !_pdfViewerController.isReady) return;
    _syncTransformationMatrix();
    if (_isDocumentLoaded) {
      final zoom = _pdfViewerController.currentZoom;
      if (zoom >= 0.2 && (zoom - _lastReportedZoom).abs() >= 0.005) {
        _lastReportedZoom = zoom;
        ReadingProgressService.instance.saveLastZoom(widget.file.path, zoom);
      }
    }
    if (!_isDraggingSelectionHandle && _selectedUnionPdfrxDocRect != null) {
      final updatedLocal = _computeLocalRectFromPdfrxDocRect(_selectedUnionPdfrxDocRect!);
      if (updatedLocal != _textSelectionLocalRectNotifier.value) {
        _textSelectionLocalRectNotifier.value = updatedLocal;
      }
    }
  }

  void _resetSelectionOverlayState() {
    _selectionSyncSerial++;
    _textSelectionLocalRectNotifier.value = null;
    if (!mounted) return;
    setState(() {
      _selectedUnionPdfrxDocRect = null;
      _selectedPageDocRects = const {};
      _selectedText = null;
      _hasActiveTextSelection = false;
      _isDraggingSelectionHandle = false;
    });
  }

  void _clearPdfTextSelection() {
    if (_pdfViewerController.isReady) {
      _pdfViewerController.textSelectionDelegate.clearTextSelection();
    }
    _resetSelectionOverlayState();
  }

  Future<void> _refreshTextSelectionFromController() async {
    if (!mounted || !_pdfViewerController.isReady) return;
    final serial = ++_selectionSyncSerial;
    final delegate = _pdfViewerController.textSelectionDelegate;
    if (!delegate.hasSelectedText) {
      if (!_isDraggingSelectionHandle) {
        _resetSelectionOverlayState();
      }
      return;
    }

    final text = await delegate.getSelectedText();
    final ranges = await delegate.getSelectedTextRanges();
    if (!mounted || serial != _selectionSyncSerial || !_pdfViewerController.isReady) {
      return;
    }
    if (text.trim().isEmpty || ranges.isEmpty) {
      if (!_isDraggingSelectionHandle) {
        _resetSelectionOverlayState();
      }
      return;
    }

    if (_contextMenuDialogContext != null) {
      try {
        Navigator.of(_contextMenuDialogContext!).pop();
      } catch (_) {}
      _contextMenuDialogContext = null;
    }

    _syncDocumentLayoutFromController();
    final pages = _pdfViewerController.pages;
    final pageLayouts = _pdfViewerController.layout.pageLayouts;
    final k = _docToCanvasScale > 0 ? _docToCanvasScale : 1.0;

    Rect? unionPdfrxRect;
    final pageRectsMap = <int, List<Rect>>{};

    for (final range in ranges) {
      final pageNum = range.pageNumber;
      final pageIdx = pageNum - 1;
      if (pageIdx < 0 || pageIdx >= pages.length || pageIdx >= pageLayouts.length) {
        continue;
      }
      final page = pages[pageIdx];
      final pageLayoutRect = pageLayouts[pageIdx];
      final rawCanvasRects = <Rect>[];

      for (final frag in range.enumerateFragmentBoundingRects()) {
        final pdfrxRect = frag.bounds.toRectInDocument(
          page: page,
          pageRect: pageLayoutRect,
        );
        if (pdfrxRect.isEmpty) continue;
        unionPdfrxRect = unionPdfrxRect == null
            ? pdfrxRect
            : unionPdfrxRect.expandToInclude(pdfrxRect);
        rawCanvasRects.add(
          Rect.fromLTRB(
            pdfrxRect.left / k,
            pdfrxRect.top / k,
            pdfrxRect.right / k,
            pdfrxRect.bottom / k,
          ),
        );
      }

      if (rawCanvasRects.isNotEmpty) {
        pageRectsMap[pageNum] = _mergeLineRects(rawCanvasRects);
      }
    }

    if (unionPdfrxRect == null || pageRectsMap.isEmpty) {
      _resetSelectionOverlayState();
      return;
    }

    _textSelectionLocalRectNotifier.value = _isDraggingSelectionHandle
        ? null
        : _computeLocalRectFromPdfrxDocRect(unionPdfrxRect);
    setState(() {
      _selectedTextAnnotationId = null;
      _selectedShapeId = null;
      _selectedStrokeId = null;
      _editingTextBoxId = null;
      _selectedUnionPdfrxDocRect = unionPdfrxRect;
      _selectedPageDocRects = pageRectsMap;
      _selectedText = text;
      _hasActiveTextSelection = true;
    });
  }

  void _onTextSelectionChange(pdfrx.PdfTextSelection textSelection) {
    if (!textSelection.hasSelectedText) {
      if (!_isDraggingSelectionHandle) {
        _resetSelectionOverlayState();
      }
      return;
    }
    _refreshTextSelectionFromController();
  }

  void _onSelectionHandlePanStart(pdfrx.PdfTextSelectionAnchor anchor) {
    _isDraggingSelectionHandle = true;
    if (_textSelectionLocalRectNotifier.value != null && mounted) {
      _textSelectionLocalRectNotifier.value = null;
    }
  }

  void _onSelectionHandlePanEnd(pdfrx.PdfTextSelectionAnchor anchor) {
    _isDraggingSelectionHandle = false;
    _refreshTextSelectionFromController();
  }

  int? _calculateInitialPageNumber(
    pdfrx.PdfDocument document,
    pdfrx.PdfViewerController controller,
  ) {
    if (document.pages.isEmpty) return 1;
    final desired = _isDocumentLoaded ? _currentPage : _initialPageNumber;
    return desired.clamp(1, document.pages.length).toInt();
  }

  void _onViewerReady(
    pdfrx.PdfDocument document,
    pdfrx.PdfViewerController controller,
  ) {
    _loadingWatchdogTimer?.cancel();
    final totalPages = document.pages.length;
    if (!mounted) return;

    final wasAlreadyLoaded = _isDocumentLoaded;
    final baseDesired = wasAlreadyLoaded ? _currentPage : _initialPageNumber;
    final int targetPage = baseDesired.clamp(1, math.max(1, totalPages)).toInt();

    final persistedZoom = ReadingProgressService.instance.getLastZoom(widget.file.path);
    final effectiveSavedZoom = persistedZoom ??
        (wasAlreadyLoaded && _lastReportedZoom >= controller.minScale ? _lastReportedZoom : null);
    final layout = controller.layout;
    final viewWidth = controller.viewSize.width > 0
        ? controller.viewSize.width
        : (_canvasSize.width > 0 ? _canvasSize.width : 0.0);

    if (totalPages > 0 && targetPage >= 1 && targetPage <= layout.pageLayouts.length && viewWidth > 0) {
      final target = computeInitialViewportTarget(
        pageLayout: layout.pageLayouts[targetPage - 1],
        viewWidth: viewWidth,
        savedZoom: effectiveSavedZoom,
        minScale: controller.minScale,
        maxScale: controller.maxScale,
      );
      controller.goToPosition(
        documentOffset: target.documentOffset,
        zoom: target.zoom,
        duration: Duration.zero,
      );
    } else if (effectiveSavedZoom != null && effectiveSavedZoom >= controller.minScale) {
      controller.setZoom(
        Offset.zero,
        effectiveSavedZoom.clamp(controller.minScale, controller.maxScale),
        duration: Duration.zero,
      );
    }

    _syncDocumentLayoutFromController();
    _lastReportedZoom = controller.currentZoom;
    _isDocumentLoaded = true;
    final actualPage = controller.pageNumber ?? targetPage;
    setState(() {
      _pagesCount = math.max(1, totalPages);
      _currentPage = actualPage;
      _isLoading = false;
    });
    if (!wasAlreadyLoaded && targetPage != _initialPageNumber) {
      _initialPageNumber = targetPage;
      ReadingProgressService.instance.saveLastPage(widget.file.path, targetPage);
    }
    widget.onPageInfoChanged?.call(_currentPage, _pagesCount);
  }

  void _onDocumentLoadFinished(pdfrx.PdfDocumentRef documentRef, bool succeeded) {
    if (!mounted) return;
    if (!succeeded) {
      _loadingWatchdogTimer?.cancel();
      final err = documentRef.resolveListenable().error;
      setState(() {
        _isLoading = false;
        _errorMessage = err?.toString() ?? 'Failed to open PDF document.';
      });
    } else if (_isDocumentLoaded && _isLoading) {
      _loadingWatchdogTimer?.cancel();
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onViewSizeChanged(
    Size viewSize,
    Size? oldViewSize,
    pdfrx.PdfViewerController controller,
  ) {
    if (!mounted || !controller.isReady) return;
    _syncDocumentLayoutFromController();
  }

  void _onPdfPageChanged(int? pageNumber) {
    if (!_isDocumentLoaded || pageNumber == null) return;
    if (_currentPage == pageNumber) return;
    _currentPage = pageNumber;
    ReadingProgressService.instance.saveLastPage(widget.file.path, _currentPage);
    widget.onPageInfoChanged?.call(_currentPage, _pagesCount);
  }

  Future<void> _handlePdfLinkTap(pdfrx.PdfLink link) async {
    if (_oneShotShape != null || _isEraserActive) {
      return;
    }
    if (!_stylusOnlyMode &&
        (_activeTool == EditorTool.pen ||
            _activeTool == EditorTool.eraser ||
            _activeTool == EditorTool.shape ||
            _activeTool == EditorTool.textBox ||
            _activeTool == EditorTool.latexBox)) {
      return;
    }

    if (link.url != null) {
      final urlString = link.url.toString();
      try {
        final success = await _stylusChannel.invokeMethod<bool>('openUrl', {'url': urlString});
        if (success != true) {
          await Clipboard.setData(ClipboardData(text: urlString));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Link copied to clipboard')),
          );
        }
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: urlString));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied to clipboard')),
        );
      }
      return;
    }

    if (link.dest != null && _pdfViewerController.isReady) {
      final dest = link.dest!;
      if (dest.pageNumber >= 1 && dest.pageNumber <= _pagesCount) {
        jumpToPage(dest.pageNumber);
      } else {
        await _pdfViewerController.goToDest(dest);
      }
    }
  }

  bool _onGeneralTap(
    BuildContext tapContext,
    pdfrx.PdfViewerController controller,
    pdfrx.PdfViewerGeneralTapHandlerDetails details,
  ) {
    if (_oneShotShape != null || _isEraserActive) {
      return true;
    }

    switch (details.type) {
      case pdfrx.PdfViewerGeneralTapType.tap:
        Future.microtask(() {
          if (!mounted || !_pdfViewerController.isReady) return;
          if (!_pdfViewerController.textSelectionDelegate.hasSelectedText &&
              (_hasActiveTextSelection || _textSelectionLocalRectNotifier.value != null)) {
            _resetSelectionOverlayState();
          }
        });
        return false;

      case pdfrx.PdfViewerGeneralTapType.doubleTap:
        if (!controller.isReady) return false;
        final docWidth = controller.layout.documentSize.width;
        final fitWidthZoom = (docWidth > 0 && controller.viewSize.width > 0)
            ? controller.viewSize.width / docWidth
            : controller.currentZoom;
        final targetZoom = controller.currentZoom > fitWidthZoom * 1.15
            ? fitWidthZoom
            : math.min(fitWidthZoom * 2.25, 8.0);
        controller.zoomOnLocalPosition(
          localPosition: details.localPosition,
          newZoom: targetZoom,
        );
        return true;

      case pdfrx.PdfViewerGeneralTapType.longPress:
      case pdfrx.PdfViewerGeneralTapType.secondaryTap:
        final isLongPress = details.type == pdfrx.PdfViewerGeneralTapType.longPress;
        if (_shouldEnableTextSelection &&
            details.tapOn == pdfrx.PdfViewerPart.selectedText) {
          _refreshTextSelectionFromController();
          return true;
        }
        if (_shouldEnableTextSelection &&
            isLongPress &&
            details.tapOn == pdfrx.PdfViewerPart.nonSelectedText) {
          if (_contextMenuDialogContext != null) {
            try {
              Navigator.of(_contextMenuDialogContext!).pop();
            } catch (_) {}
            _contextMenuDialogContext = null;
          }
          setState(() {
            _selectedTextAnnotationId = null;
            _selectedShapeId = null;
            _selectedStrokeId = null;
            _editingTextBoxId = null;
            _hasActiveTextSelection = true;
          });
          Future.delayed(
            const Duration(milliseconds: 45),
            _refreshTextSelectionFromController,
          );
          return false;
        }

        _clearPdfTextSelection();
        final globalPos = controller.localToGlobal(details.localPosition) ??
            (context.findRenderObject() as RenderBox?)?.localToGlobal(details.localPosition) ??
            details.localPosition;
        final k = _docToCanvasScale > 0 ? _docToCanvasScale : 1.0;
        final canvasDocPos = Offset(
          details.documentPosition.dx / k,
          details.documentPosition.dy / k,
        );
        _showNonTextContextMenu(globalPos, canvasDocPos);
        return true;
    }
  }

  DateTime? _lastButtonDownTime;
  DateTime? _lastButtonToggleTime;

  void _toggleEraserMode() {
    final now = DateTime.now();
    if (_lastButtonToggleTime != null &&
        now.difference(_lastButtonToggleTime!).inMilliseconds <= 200) {
      return;
    }
    _lastButtonToggleTime = now;
    setState(() {
      final nextIsEraser = !_isEraserActive;
      _isHardwareButtonPressed = nextIsEraser;
      _activeTool = nextIsEraser ? EditorTool.eraser : EditorTool.pen;
    });
    _drawingController.cancelActiveStroke();
  }

  Future<void> handleStylusPlatformCall(MethodCall call) async {
    if (!mounted) return;
    _onStylusDetected();

    if (call.method == 'onStylusButtonDown') {
      _lastButtonDownTime = DateTime.now();
      _toggleEraserMode();
    } else if (call.method == 'onStylusButtonUp') {
      final now = DateTime.now();
      if (_lastButtonDownTime == null ||
          now.difference(_lastButtonDownTime!).inMilliseconds > 300) {
        _toggleEraserMode();
      }
      _lastButtonDownTime = null;
    }
  }

  Future<bool> _promptSaveIfDirty() async {
    if (_editingTextBoxId != null && mounted) {
      setState(() {
        _editingTextBoxId = null;
      });
    }

    final hasPageChanges = _deletedZeroIndexedPages.isNotEmpty || _addedPagesCount > 0;
    if (!hasPageChanges && !_drawingController.hasAnnotations) {
      if (_originalBaseBytes != null) {
        await _saveToOriginalFile(showFeedback: false);
      }
      return true;
    }

    if (!_hasUnsavedChanges) return true;
    if (!mounted || !context.mounted) return true;

    try {
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
              SizedBox(width: 8),
              Text('Save Changes?'),
            ],
          ),
          content: const Text(
            'You have unsaved annotations. Do you want to save them before leaving?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'discard'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Discard'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: const Text('Save & Exit'),
            ),
          ],
        ),
      );

      if (result == 'discard') {
        _drawingController.markSaved();
        _deletedZeroIndexedPages.clear();
        _addedPagesCount = 0;
        _notifyDirtyIfChanged();
        return true;
      } else if (result == 'save') {
        final success = await _saveToOriginalFile(showFeedback: false);
        return success;
      } else {
        return false;
      }
    } catch (_) {
      return true;
    }
  }

  Future<void> _reloadDocumentAfterSave() async {
    if (!mounted) return;
    _isDocumentLoaded = false;
    _reloadGeneration++;
    _baseNormalizedWidth = null;
    _pageDocBounds.clear();
    _rebuildDocumentRef();
    _startLoadingWatchdog();
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });
  }

  void _onToolSelected(EditorTool tool) {
    final willEnableSelection = _oneShotShape == null &&
        (_stylusOnlyMode || _isStylusDetected || tool == EditorTool.select);
    if (!willEnableSelection) {
      _clearPdfTextSelection();
    }
    setState(() {
      _activeTool = tool;
      _isHardwareButtonPressed = tool == EditorTool.eraser;
      _selectedTextAnnotationId = null;
    });
  }

  void _onColorSelected(Color color) {
    bool controllerNotified = false;
    _activeColor = color;
    if (_selectedShapeId != null) {
      final shape = _drawingController.shapes.cast<DrawnShape?>().firstWhere(
        (s) => s?.id == _selectedShapeId,
        orElse: () => null,
      );
      if (shape != null) {
        shape.color = color;
        _drawingController.updateDrawnShape(shape);
        controllerNotified = true;
      }
    }
    if (_selectedStrokeId != null) {
      final stroke = _drawingController.strokes.cast<DrawingStroke?>().firstWhere(
        (s) => s?.id == _selectedStrokeId,
        orElse: () => null,
      );
      if (stroke != null) {
        stroke.color = color;
        _drawingController.updateStroke(stroke);
        controllerNotified = true;
      }
    }
    if (_editingTextBoxId != null) {
      final tb = _drawingController.textBoxes.cast<DrawnTextBox?>().firstWhere(
        (t) => t?.id == _editingTextBoxId,
        orElse: () => null,
      );
      if (tb != null) {
        tb.color = color;
        _drawingController.updateTextBox(tb);
        controllerNotified = true;
      }
    }
    if (!controllerNotified) {
      setState(() {});
    }
    _saveSettings();
  }

  void _onStrokeWidthSelected(double width) {
    bool controllerNotified = false;
    _activeStrokeWidth = width;
    if (_selectedShapeId != null) {
      final shape = _drawingController.shapes.cast<DrawnShape?>().firstWhere(
        (s) => s?.id == _selectedShapeId,
        orElse: () => null,
      );
      if (shape != null) {
        shape.strokeWidth = width;
        _drawingController.updateDrawnShape(shape);
        controllerNotified = true;
      }
    }
    if (_selectedStrokeId != null) {
      final stroke = _drawingController.strokes.cast<DrawingStroke?>().firstWhere(
        (s) => s?.id == _selectedStrokeId,
        orElse: () => null,
      );
      if (stroke != null) {
        stroke.strokeWidth = width;
        _drawingController.updateStroke(stroke);
        controllerNotified = true;
      }
    }
    if (!controllerNotified) {
      setState(() {});
    }
    _saveSettings();
  }

  void _onFontSizeSelected(double fontSize) {
    bool controllerNotified = false;
    _activeFontSize = fontSize;
    if (_editingTextBoxId != null) {
      final tb = _drawingController.textBoxes.cast<DrawnTextBox?>().firstWhere(
        (t) => t?.id == _editingTextBoxId,
        orElse: () => null,
      );
      if (tb != null) {
        tb.fontSize = fontSize;
        _drawingController.updateTextBox(tb);
        controllerNotified = true;
      }
    }
    if (!controllerNotified) {
      setState(() {});
    }
  }

  void _onShapeSelected(ShapeType shape) {
    setState(() {
      _activeShape = shape;
    });
    _saveSettings();
  }

  void _onStylusDetected() {
    final shouldSwitchToPen = _activeTool == EditorTool.select;
    if (!_isStylusDetected || !_stylusOnlyMode || shouldSwitchToPen) {
      setState(() {
        _isStylusDetected = true;
        _stylusOnlyMode = true;
        if (shouldSwitchToPen) {
          _activeTool = EditorTool.pen;
        }
      });
    }
  }

  void _onStylusDrawStarted() {
    _onStylusDetected();
    if (_isEraserActive || _activeTool == EditorTool.eraser) return;
    if (_activeTool != EditorTool.pen && _activeTool != EditorTool.shape) {
      setState(() {
        _activeTool = EditorTool.pen;
      });
    }
  }

  void _addInlineTextBox(Offset position) {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final newBox = DrawnTextBox(
      id: newId,
      text: '',
      position: position,
      color: _activeColor,
      fontSize: _activeFontSize,
      pageNumber: _currentPage,
      width: 220.0,
    );
    _drawingController.addTextBox(newBox);
    setState(() {
      _editingTextBoxId = newId;
      _activeTool = EditorTool.select;
    });
  }

  void _addInlineLatexBox(Offset position) {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final newBox = DrawnTextBox(
      id: newId,
      text: r'\frac{a}{b}',
      position: position,
      color: _activeColor,
      fontSize: math.max(18.0, _activeFontSize),
      pageNumber: _currentPage,
      width: 180.0,
      isLatex: true,
    );
    _drawingController.addTextBox(newBox);
    setState(() {
      _editingTextBoxId = newId;
      _activeTool = EditorTool.select;
    });
  }

  BuildContext? _contextMenuDialogContext;

  void _showNonTextContextMenu(Offset screenPos, Offset docPos) {
    if (_hasActiveTextSelection || _isEraserActive) return;
    HapticFeedback.lightImpact();

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.15),
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, anim1, anim2) {
        _contextMenuDialogContext = dialogContext;
        final theme = Theme.of(context);
        final screenSize = MediaQuery.of(context).size;
        const menuWidth = 230.0;
        const menuHeight = 245.0;
        final left = screenPos.dx.clamp(16.0, screenSize.width - menuWidth - 16.0);
        final top = screenPos.dy.clamp(60.0, screenSize.height - menuHeight - 16.0);

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(16),
                color: theme.colorScheme.surface,
                shadowColor: Colors.black45,
                child: Container(
                  width: menuWidth,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.category_outlined, size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                            const Text(
                              'Draw Shape',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildShapeQuickAction(dialogContext, ShapeType.rectangle, Icons.rectangle_outlined, 'Rectangle'),
                          _buildShapeQuickAction(dialogContext, ShapeType.circle, Icons.circle_outlined, 'Circle'),
                          _buildShapeQuickAction(dialogContext, ShapeType.line, Icons.horizontal_rule_rounded, 'Line'),
                          _buildShapeQuickAction(dialogContext, ShapeType.arrow, Icons.arrow_forward_rounded, 'Arrow'),
                        ],
                      ),
                      const Divider(height: 14),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _addInlineTextBox(docPos);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: Row(
                            children: [
                              Icon(Icons.title_rounded, size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              const Text(
                                'Add TextBox',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 14),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _addInlineLatexBox(docPos);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: Row(
                            children: [
                              Icon(Icons.functions_rounded, size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              const Text(
                                'Add LaTeX Formula',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 14),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _handlePaste(docPos);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: Row(
                            children: [
                              Icon(Icons.content_paste_rounded, size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              const Text(
                                'Paste (Text or Image)',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      _contextMenuDialogContext = null;
    });
  }

  Future<void> _handlePaste(Offset docPos) async {
    try {
      final imageBytes = await _stylusChannel.invokeMethod<Uint8List>('getClipboardImage');
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final codec = await ui.instantiateImageCodec(imageBytes);
        final frame = await codec.getNextFrame();
        final img = frame.image;
        final aspect = img.width / img.height;
        img.dispose();
        codec.dispose();

        const defaultWidth = 220.0;
        final defaultHeight = defaultWidth / aspect;

        final newImg = DrawnImage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          imageBytes: imageBytes,
          position: docPos,
          width: defaultWidth,
          height: defaultHeight,
          pageNumber: _currentPage,
        );
        _drawingController.addImage(newImg);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image pasted from clipboard!'), duration: Duration(seconds: 2)),
          );
        }
        return;
      }
    } catch (_) {}

    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text?.trim();
      if (text != null && text.isNotEmpty) {
        final newBox = DrawnTextBox(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: text,
          position: docPos,
          color: _activeColor,
          fontSize: _activeFontSize,
          pageNumber: _currentPage,
          width: 220.0,
        );
        _drawingController.addTextBox(newBox);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Text pasted from clipboard!'), duration: Duration(seconds: 2)),
          );
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clipboard is empty (no text or image found).'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildShapeQuickAction(
    BuildContext dialogContext,
    ShapeType shape,
    IconData icon,
    String tooltip,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.pop(dialogContext);
          setState(() {
            _oneShotShape = shape;
          });
        },
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }

  void _openPageManager() async {
    final result = await showDialog<PageManagerResult>(
      context: context,
      builder: (context) => PdfPageManagerDialog(
        file: widget.file,
        totalPages: _pagesCount,
        currentPage: _currentPage,
        initialDeletedZeroIndexedPages: _deletedZeroIndexedPages,
        initialAddedPagesCount: _addedPagesCount,
      ),
    );

    if (!mounted) return;

    if (result != null) {
      setState(() {
        _deletedZeroIndexedPages = List<int>.from(result.deletedZeroIndexedPages);
        _addedPagesCount = result.addedPagesCount;
      });
      _notifyDirtyIfChanged();

      if (_deletedZeroIndexedPages.isNotEmpty || _addedPagesCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Page changes staged (Deleted: ${_deletedZeroIndexedPages.length}, Added: $_addedPagesCount). Tap Save to apply to file.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<bool> _saveToOriginalFile({bool showFeedback = true}) async {
    if (_isSaving) return false;
    _isSaving = true;

    if (_editingTextBoxId != null && mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _editingTextBoxId = null;
      });
      await WidgetsBinding.instance.endOfFrame;
    }

    try {
      final file = File(widget.file.path);
      _originalBaseBytes ??= await file.readAsBytes();

      final hasPageStructureChange = _deletedZeroIndexedPages.isNotEmpty || _addedPagesCount > 0;
      _syncDocumentLayoutFromController();
      final viewportWidth = _baseNormalizedWidth ?? (_canvasSize.width > 0 ? _canvasSize.width : 400.0);

      final finalBytes = await PdfExportService.exportToFile(
        file: file,
        baseBytes: _originalBaseBytes!,
        drawingController: _drawingController,
        viewportWidth: viewportWidth,
        textBoxFont: _textBoxFont,
        deletedZeroIndexedPages: _deletedZeroIndexedPages,
        addedPagesCount: _addedPagesCount,
        pageDocBounds: _pageDocBounds.isNotEmpty ? _pageDocBounds : null,
      );

      // Invalidate thumbnail cache and refresh open tab file metadata
      PdfThumbnailService.instance.invalidate(file.path);
      try {
        PdfTabManager.instance.renameTab(file.path, PdfFileInfo.fromFile(file));
      } catch (_) {}

      _drawingController.markSaved();

      if (hasPageStructureChange) {
        final deletedBeforeCurrent = _deletedZeroIndexedPages
            .where((zeroIdx) => zeroIdx < (_currentPage - 1))
            .length;
        final newTotalPages = math.max(
          1,
          _pagesCount - _deletedZeroIndexedPages.length + _addedPagesCount,
        );
        final int adjustedPage = (_currentPage - deletedBeforeCurrent).clamp(1, newTotalPages).toInt();
        _initialPageNumber = adjustedPage;
        _currentPage = adjustedPage;
        ReadingProgressService.instance.saveLastPage(
          file.path,
          adjustedPage,
          immediate: true,
        );

        _originalBaseBytes = finalBytes;
        _deletedZeroIndexedPages.clear();
        _addedPagesCount = 0;
        _drawingController.clearAll();
        if (mounted) {
          await _reloadDocumentAfterSave();
        }
      }

      _notifyDirtyIfChanged();

      if (mounted && showFeedback) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Successfully saved to original file!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted && showFeedback) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save file: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    } finally {
      _isSaving = false;
    }
  }

  Future<void> _openExternal() async {
    try {
      final result = await OpenFilex.open(widget.file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open external app: ${result.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _createTextAnnotationFromSelection(TextAnnotationType type) async {
    if (_selectedPageDocRects.isEmpty && _pdfViewerController.isReady) {
      await _refreshTextSelectionFromController();
    }
    if (!mounted) return;
    if (_selectedPageDocRects.isEmpty) {
      _clearPdfTextSelection();
      return;
    }

    Color color;
    if (type == TextAnnotationType.highlight) {
      color = _highlightColor;
    } else if (type == TextAnnotationType.underline) {
      color = _underlineColor;
    } else {
      color = const Color(0xFFF44336);
    }

    for (final entry in _selectedPageDocRects.entries) {
      if (entry.value.isEmpty) continue;
      final annotation = DrawnTextAnnotation(
        type: type,
        rects: List<Rect>.from(entry.value),
        color: color,
        pageNumber: entry.key,
      );
      _drawingController.addTextAnnotation(annotation);
    }

    _clearPdfTextSelection();
    _notifyDirtyIfChanged();
  }

  bool get hasUnsavedChanges => _hasUnsavedChanges;

  Future<bool> promptSaveIfDirty() => _promptSaveIfDirty();

  bool handleBackPress() {
    if (_selectedTextAnnotationId != null) {
      setState(() => _selectedTextAnnotationId = null);
      return true;
    }
    if (_textSelectionLocalRectNotifier.value != null) {
      _clearPdfTextSelection();
      return true;
    }
    if (_selectedShapeId != null) {
      setState(() => _selectedShapeId = null);
      return true;
    }
    if (_selectedStrokeId != null) {
      setState(() => _selectedStrokeId = null);
      return true;
    }
    if (_editingTextBoxId != null) {
      setState(() => _editingTextBoxId = null);
      return true;
    }
    if (_hasActiveTextSelection) {
      _clearPdfTextSelection();
      return true;
    }
    final route = ModalRoute.of(context);
    if (route != null && route.willHandlePopInternally) {
      route.didPop(null);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final selectedShape = _selectedShapeId != null
        ? _drawingController.shapes.cast<DrawnShape?>().firstWhere(
              (s) => s?.id == _selectedShapeId,
              orElse: () => null,
            )
        : null;
    final selectedStroke = _selectedStrokeId != null
        ? _drawingController.strokes.cast<DrawingStroke?>().firstWhere(
              (s) => s?.id == _selectedStrokeId,
              orElse: () => null,
            )
        : null;
    final editingTextBox = _editingTextBoxId != null
        ? _drawingController.textBoxes.cast<DrawnTextBox?>().firstWhere(
              (t) => t?.id == _editingTextBoxId,
              orElse: () => null,
            )
        : null;
    final selectedTextAnnotation = _selectedTextAnnotationId != null
        ? _drawingController.textAnnotations.cast<DrawnTextAnnotation?>().firstWhere(
              (ta) => ta?.id == _selectedTextAnnotationId,
              orElse: () => null,
            )
        : null;

    return _errorMessage != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, size: 64, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(
                    'Unable to load PDF',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          _reloadGeneration++;
                          _baseNormalizedWidth = null;
                          _rebuildDocumentRef();
                          setState(() {
                            _errorMessage = null;
                            _isLoading = true;
                          });
                          _startLoadingWatchdog();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _openExternal,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open with External App'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        : Listener(
            behavior: HitTestBehavior.translucent,
            onPointerHover: (event) {
              if (event.kind == PointerDeviceKind.stylus ||
                  event.kind == PointerDeviceKind.invertedStylus) {
                _onStylusDetected();
              }
            },
            onPointerDown: (event) {
              if (event.kind == PointerDeviceKind.stylus ||
                  event.kind == PointerDeviceKind.invertedStylus) {
                _onStylusDetected();
                if (!_isEraserActive && _activeTool != EditorTool.eraser) {
                  _onStylusDrawStarted();
                }
              }
            },
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final newSize = Size(constraints.maxWidth, constraints.maxHeight);
                    if (_canvasSize != newSize) {
                      _canvasSize = newSize;
                      if (newSize.width > 0 && _baseNormalizedWidth == null) {
                        _baseNormalizedWidth = newSize.width;
                      }
                    }
                    return PassThroughStack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          child: pdfrx.PdfViewer(
                            _documentRef,
                            controller: _pdfViewerController,
                            fontManager: PdfSystemFontService.instance.fontManager,
                            initialPageNumber: _initialPageNumber,
                            params: pdfrx.PdfViewerParams(
                              margin: 0.0,
                              layoutPages: _layoutVerticalPages,
                              buildContextMenu: _suppressBuiltInContextMenu,
                              backgroundColor: theme.brightness == Brightness.dark
                                  ? const Color(0xFF1A1C1E)
                                  : const Color(0xFFE8EAED),
                              pageDropShadow: const BoxShadow(
                                color: Colors.black26,
                                blurRadius: 3,
                                spreadRadius: 0,
                                offset: Offset(0, 1),
                              ),
                              scrollPhysics: const ClampingScrollPhysics(),
                              sizeDelegateProvider: const _DeferredInitSmartSizeDelegateProvider(
                                inner: pdfrx.PdfViewerSizeDelegateProviderSmart(
                                  smartMaxScale: double.infinity,
                                  minScale: 0.2,
                                  maxScale: 8.0,
                                  maxPagesVisible: double.infinity,
                                  onePassRenderingScaleThreshold: 220 / 72,
                                ),
                              ),
                              maxImageBytesCachedOnMemory: 96 * 1024 * 1024,
                              verticalCacheExtent: 1.2,
                              horizontalCacheExtent: 0.5,
                              panEnabled: _shouldAllowViewerPan,
                              scaleEnabled: _oneShotShape == null,
                              textSelectionParams: pdfrx.PdfTextSelectionParams(
                                enabled: _shouldEnableTextSelection,
                                enableSelectionHandles: true,
                                showContextMenuAutomatically: false,
                                onTextSelectionChange: _onTextSelectionChange,
                                onSelectionHandlePanStart: _onSelectionHandlePanStart,
                                onSelectionHandlePanEnd: _onSelectionHandlePanEnd,
                              ),
                              calculateInitialPageNumber: _calculateInitialPageNumber,
                              onViewerReady: _onViewerReady,
                              onDocumentLoadFinished: _onDocumentLoadFinished,
                              onViewSizeChanged: _onViewSizeChanged,
                              onPageChanged: _onPdfPageChanged,
                              onGeneralTap: _onGeneralTap,
                              linkHandlerParams: pdfrx.PdfLinkHandlerParams(
                                onLinkTap: _handlePdfLinkTap,
                                linkColor: Colors.transparent,
                                enableAutoLinkDetection: true,
                              ),
                            ),
                          ),
                        ),
                        RepaintBoundary(
                          child: PdfEditorCanvas(
                            controller: _drawingController,
                            transformationController: _transformationController,
                            activeTool: _activeTool,
                            activeShape: _activeShape,
                            activeColor: _activeColor,
                            activeStrokeWidth: _activeStrokeWidth,
                            textBoxFont: _textBoxFont,
                            currentPage: _currentPage,
                            currentPageGetter: () => _currentPage,
                            stylusOnlyMode: _stylusOnlyMode,
                            isStylusDetected: _isStylusDetected,
                            isHardwareButtonPressed: _isEraserActive,
                            oneShotShape: _oneShotShape,
                            onOneShotShapeCompleted: () {
                              setState(() {
                                _oneShotShape = null;
                                if (_drawingController.shapes.isNotEmpty) {
                                  _selectedShapeId = _drawingController.shapes.last.id;
                                  _selectedStrokeId = null;
                                  _selectedTextAnnotationId = null;
                                }
                              });
                              _notifyDirtyIfChanged();
                            },
                            onCancelOneShotShape: () => setState(() => _oneShotShape = null),
                            hasActiveTextSelection: _hasActiveTextSelection,
                            editingTextBoxId: _editingTextBoxId,
                            onEditingTextBoxChanged: (id) {
                              if (mounted) {
                                setState(() {
                                  _editingTextBoxId = id;
                                  if (id != null) {
                                    _selectedTextAnnotationId = null;
                                    _selectedShapeId = null;
                                    _selectedStrokeId = null;
                                  } else if (_activeTool == EditorTool.textBox ||
                                      _activeTool == EditorTool.latexBox) {
                                    _activeTool = EditorTool.select;
                                  }
                                });
                              }
                            },
                            selectedShapeId: _selectedShapeId,
                            onSelectedShapeChanged: (id) {
                              if (mounted) {
                                setState(() {
                                  _selectedShapeId = id;
                                  if (id != null) {
                                    _selectedTextAnnotationId = null;
                                    _selectedStrokeId = null;
                                    _editingTextBoxId = null;
                                  }
                                });
                              }
                            },
                            selectedStrokeId: _selectedStrokeId,
                            onSelectedStrokeChanged: (id) {
                              if (mounted) {
                                setState(() {
                                  _selectedStrokeId = id;
                                  if (id != null) {
                                    _selectedTextAnnotationId = null;
                                    _selectedShapeId = null;
                                    _editingTextBoxId = null;
                                  }
                                });
                              }
                            },
                            selectedTextAnnotationId: _selectedTextAnnotationId,
                            onSelectedTextAnnotationChanged: (id) {
                              if (mounted) {
                                setState(() {
                                  _selectedTextAnnotationId = id;
                                  if (id != null) {
                                    _selectedShapeId = null;
                                    _selectedStrokeId = null;
                                    _editingTextBoxId = null;
                                  }
                                });
                              }
                            },
                            onPointerEraserStateChanged: (pressed) {
                              if (_isPointerButtonPressed != pressed) {
                                setState(() {
                                  _isPointerButtonPressed = pressed;
                                });
                                if (pressed) {
                                  _drawingController.cancelActiveStroke();
                                }
                              }
                            },
                            onAddTextBoxRequested: _addInlineTextBox,
                            onAddLatexBoxRequested: _addInlineLatexBox,
                            onShapeCompleted: () {
                              setState(() {
                                _activeTool = EditorTool.select;
                                if (_drawingController.shapes.isNotEmpty) {
                                  _selectedShapeId = _drawingController.shapes.last.id;
                                  _selectedStrokeId = null;
                                  _selectedTextAnnotationId = null;
                                }
                              });
                              _notifyDirtyIfChanged();
                            },
                            onStylusDetected: _onStylusDetected,
                            onStylusDrawStarted: _onStylusDrawStarted,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (_selectedText != null)
                  ValueListenableBuilder<Rect?>(
                    valueListenable: _textSelectionLocalRectNotifier,
                    builder: (context, localRect, _) {
                      if (localRect == null) return const SizedBox.shrink();
                      return _buildTextSelectionMenu(localRect);
                    },
                  ),
                PdfFloatingToolbar(
                  activeTool: _activeTool,
                  activeShape: _activeShape,
                  activeColor: _activeColor,
                  activeStrokeWidth: _activeStrokeWidth,
                  activeFontSize: _activeFontSize,
                  isStylusDetected: _isStylusDetected,
                  isEraserActive: _isEraserActive,
                  stylusOnlyMode: _stylusOnlyMode,
                  canUndo: _drawingController.canUndo,
                  initialPosition: _toolbarPosition,
                  onPositionChanged: (newPos) {
                    _toolbarPosition = newPos;
                    _saveSettings();
                  },
                  initialIsCollapsed: _toolbarCollapsed,
                  onCollapsedChanged: (collapsed) {
                    _toolbarCollapsed = collapsed;
                    _saveSettings();
                  },
                  onToolSelected: _onToolSelected,
                  onShapeSelected: _onShapeSelected,
                  onColorSelected: _onColorSelected,
                  onStrokeWidthSelected: _onStrokeWidthSelected,
                  onFontSizeSelected: _onFontSizeSelected,
                  onStylusOnlyModeToggled: (mode) => setState(() => _stylusOnlyMode = mode),
                  onUndo: () => _drawingController.undo(),
                  onManagePages: _openPageManager,
                  onSave: () => _saveToOriginalFile(showFeedback: true),
                ),
                if (_isLoading)
                  Container(
                    color: _isDocumentLoaded
                        ? Colors.black26
                        : (theme.brightness == Brightness.dark
                            ? const Color(0xFF1A1C1E)
                            : const Color(0xFFE8EAED)),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                PdfAnnotationPropertyBar(
                  activeTextAnnotation: selectedTextAnnotation,
                  activeShape: selectedShape,
                  activeStroke: selectedStroke,
                  activeTextBox: editingTextBox,
                  onTextAnnotationColorChanged: (color) {
                    if (selectedTextAnnotation == null) return;
                    selectedTextAnnotation.color = color;
                    if (selectedTextAnnotation.type == TextAnnotationType.highlight) {
                      _highlightColor = color;
                    } else if (selectedTextAnnotation.type == TextAnnotationType.underline) {
                      _underlineColor = color;
                    }
                    _drawingController.updateTextAnnotation(selectedTextAnnotation);
                    _saveSettings();
                  },
                  onDeleteTextAnnotation: () {
                    if (selectedTextAnnotation == null) return;
                    _selectedTextAnnotationId = null;
                    _drawingController.deleteTextAnnotation(selectedTextAnnotation.id);
                  },
                  onDoneTextAnnotation: () {
                    setState(() => _selectedTextAnnotationId = null);
                  },
                  onShapeStrokeWidthChanged: (newWidth) {
                    if (selectedShape == null) return;
                    selectedShape.strokeWidth = newWidth;
                    _drawingController.updateDrawnShape(selectedShape);
                  },
                  onShapeColorChanged: (color) {
                    if (selectedShape == null) return;
                    selectedShape.color = color;
                    _drawingController.updateDrawnShape(selectedShape);
                  },
                  onDeleteShape: () {
                    if (selectedShape == null) return;
                    _selectedShapeId = null;
                    _drawingController.deleteDrawnShape(selectedShape.id);
                  },
                  onDoneShape: () {
                    setState(() => _selectedShapeId = null);
                  },
                  onStrokeWidthChanged: (newWidth) {
                    if (selectedStroke == null) return;
                    selectedStroke.strokeWidth = newWidth;
                    _drawingController.updateStroke(selectedStroke);
                  },
                  onStrokeColorChanged: (color) {
                    if (selectedStroke == null) return;
                    selectedStroke.color = color;
                    _drawingController.updateStroke(selectedStroke);
                  },
                  onDeleteStroke: () {
                    if (selectedStroke == null) return;
                    _selectedStrokeId = null;
                    _drawingController.deleteStroke(selectedStroke.id);
                  },
                  onDoneStroke: () {
                    setState(() => _selectedStrokeId = null);
                  },
                  onTextBoxFontSizeChanged: (newSize) {
                    if (editingTextBox == null) return;
                    editingTextBox.fontSize = newSize;
                    _activeFontSize = newSize;
                    _drawingController.updateTextBox(editingTextBox);
                    _saveSettings();
                  },
                  onTextBoxColorChanged: (color) {
                    if (editingTextBox == null) return;
                    editingTextBox.color = color;
                    _drawingController.updateTextBox(editingTextBox);
                  },
                  onDeleteTextBox: () {
                    if (editingTextBox == null) return;
                    _editingTextBoxId = null;
                    if (_activeTool == EditorTool.textBox || _activeTool == EditorTool.latexBox) {
                      _activeTool = EditorTool.select;
                    }
                    _drawingController.deleteTextBox(editingTextBox.id);
                  },
                  onDoneTextBox: () {
                    setState(() {
                      _editingTextBoxId = null;
                      if (_activeTool == EditorTool.textBox || _activeTool == EditorTool.latexBox) {
                        _activeTool = EditorTool.select;
                      }
                    });
                  },
                ),
              ],
            ),
          );
  }

  Widget _buildTextSelectionMenu(Rect localRect) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    const menuHeight = 44.0;
    const idealMenuWidth = 360.0;
    final maxAllowedWidth = math.max(120.0, math.min(idealMenuWidth, screenWidth - 24.0));

    final selCenter = localRect.center.dx;
    double left = selCenter - (maxAllowedWidth / 2);
    if (left + maxAllowedWidth > screenWidth - 12.0) {
      left = screenWidth - maxAllowedWidth - 12.0;
    }
    if (left < 12.0) {
      left = 12.0;
    }

    double top = localRect.top - menuHeight - 10.0;
    if (top < 56.0) {
      top = localRect.bottom + 10.0;
    }
    if (top > screenHeight - menuHeight - 16.0) {
      top = screenHeight - menuHeight - 16.0;
    }
    if (top < 8.0) {
      top = 8.0;
    }

    final theme = Theme.of(context);

    return Positioned(
      left: left,
      top: top,
      child: TapRegion(
        groupId: kEditableElementRegionGroup,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(22),
          color: theme.colorScheme.surface,
          shadowColor: Colors.black45,
          child: Container(
            height: menuHeight,
            constraints: BoxConstraints(maxWidth: maxAllowedWidth),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 4),
                  _buildTextMenuItem(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: _selectedText ?? ''));
                      _clearPdfTextSelection();
                    },
                  ),
                  Container(
                    height: 20,
                    width: 1,
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                  _buildTextMenuItem(
                    icon: Icons.border_color_rounded,
                    iconColor: _highlightColor,
                    label: 'Highlight',
                    onTap: () => _createTextAnnotationFromSelection(TextAnnotationType.highlight),
                  ),
                  _buildTextMenuItem(
                    icon: Icons.format_underlined_rounded,
                    iconColor: _underlineColor,
                    label: 'Underline',
                    onTap: () => _createTextAnnotationFromSelection(TextAnnotationType.underline),
                  ),
                  _buildTextMenuItem(
                    icon: Icons.format_strikethrough_rounded,
                    iconColor: const Color(0xFFF44336),
                    label: 'Strike',
                    onTap: () => _createTextAnnotationFromSelection(TextAnnotationType.strikethrough),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextMenuItem({
    required IconData icon,
    required String label,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor ?? theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeferredInitSmartSizeDelegateProvider extends pdfrx.PdfViewerSizeDelegateProvider {
  const _DeferredInitSmartSizeDelegateProvider({required this.inner});

  final pdfrx.PdfViewerSizeDelegateProviderSmart inner;

  @override
  pdfrx.PdfViewerSizeDelegate create() => _DeferredInitSmartSizeDelegate(inner.create());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _DeferredInitSmartSizeDelegateProvider && other.inner == inner);

  @override
  int get hashCode => inner.hashCode;
}

class _DeferredInitSmartSizeDelegate implements pdfrx.PdfViewerSizeDelegate {
  _DeferredInitSmartSizeDelegate(this._inner);

  final pdfrx.PdfViewerSizeDelegate _inner;

  @override
  double get onePassRenderingScaleThreshold => _inner.onePassRenderingScaleThreshold;

  @override
  void init(pdfrx.PdfViewerController controller) => _inner.init(controller);

  @override
  void dispose() => _inner.dispose();

  @override
  pdfrx.PdfViewerLayoutMetrics calculateMetrics({
    required Size viewSize,
    required pdfrx.PdfPageLayout? layout,
    required int? pageNumber,
    required double pageMargin,
    required EdgeInsets? boundaryMargin,
  }) => _inner.calculateMetrics(
    viewSize: viewSize,
    layout: layout,
    pageNumber: pageNumber,
    pageMargin: pageMargin,
    boundaryMargin: boundaryMargin,
  );

  @override
  void onLayoutInitialized({
    required pdfrx.PdfViewerLayoutSnapshot state,
    required int initialPageNumber,
    required double coverScale,
    required double? alternativeFitScale,
    required pdfrx.PdfPageLayout layout,
    required pdfrx.PdfDocument document,
  }) {
    // Initial zoom and viewport offset are applied synchronously in _onViewerReady.
  }

  @override
  void onLayoutUpdate({
    required pdfrx.PdfViewerLayoutSnapshot oldState,
    required pdfrx.PdfViewerLayoutSnapshot newState,
    required double currentZoom,
    required Rect oldVisibleRect,
    required int? anchorPageNumber,
    required bool isLayoutChanged,
    required bool isViewSizeChanged,
  }) => _inner.onLayoutUpdate(
    oldState: oldState,
    newState: newState,
    currentZoom: currentZoom,
    oldVisibleRect: oldVisibleRect,
    anchorPageNumber: anchorPageNumber,
    isLayoutChanged: isLayoutChanged,
    isViewSizeChanged: isViewSizeChanged,
  );
}

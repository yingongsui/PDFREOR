import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/pdf_file_info.dart';
import '../services/pdf_tab_manager.dart';
import '../services/reading_progress_service.dart';
import '../widgets/pdf_thumbnails_sidebar.dart';
import 'viewer/pdf_tab_content.dart';
import 'viewer/pdf_viewer_tab_bar.dart';

export 'viewer/pdf_tab_content.dart' show PdfTabContent, PdfTabContentState;

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
  bool _isBackHandling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.file != null &&
        PdfTabManager.instance.activeFile?.path != widget.file!.path) {
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
    PdfTabManager.instance.closeTabByPath(file.path);

    if (PdfTabManager.instance.tabCount == 0 && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleBack() async {
    if (_isBackHandling) return;
    _isBackHandling = true;
    try {
      final active = PdfTabManager.instance.activeFile;
      if (active != null) {
        final activeState = _tabKeys[active.path]?.currentState;
        if (activeState != null && activeState.handleBackPress()) {
          return;
        }
      }

      // Check all open tabs for unsaved changes before exiting to library
      final tabsSnapshot = List<PdfFileInfo>.from(PdfTabManager.instance.openTabs);
      for (final tab in tabsSnapshot) {
        final state = _tabKeys[tab.path]?.currentState;
        if (state != null && state.hasUnsavedChanges) {
          final currentIdx = PdfTabManager.instance.openTabs
              .indexWhere((t) => t.path == tab.path);
          if (currentIdx != -1 && currentIdx != PdfTabManager.instance.activeIndex) {
            PdfTabManager.instance.setActiveIndex(currentIdx);
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
    } finally {
      _isBackHandling = false;
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
            child: PdfViewerTabBar(
              tabs: tabs,
              activeIndex: activeIdx,
              isTabDirty: (file) =>
                  _tabKeys[file.path]?.currentState?.hasUnsavedChanges ?? false,
              onSelectTab: (index) => PdfTabManager.instance.setActiveIndex(index),
              onCloseTab: _closeTab,
            ),
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

}

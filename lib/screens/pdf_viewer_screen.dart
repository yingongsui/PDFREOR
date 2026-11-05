import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../controllers/drawing_controller.dart';
import '../models/editor_models.dart';
import '../models/pdf_file_info.dart';
import '../services/editor_settings_service.dart';
import '../services/pdf_tab_manager.dart';
import '../services/pdf_thumbnail_service.dart';
import '../widgets/pass_through_stack.dart';
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

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final Map<String, GlobalKey<PdfTabContentState>> _tabKeys = {};
  final Set<String> _activatedTabPaths = {};

  int _activeCurrentPage = 1;
  int _activePagesCount = 1;

  @override
  void initState() {
    super.initState();
    if (widget.file != null) {
      PdfTabManager.instance.openTab(widget.file!);
    }
    PdfTabManager.instance.addListener(_onTabManagerChanged);
  }

  @override
  void dispose() {
    PdfTabManager.instance.removeListener(_onTabManagerChanged);
    super.dispose();
  }

  void _syncActivePageInfo() {
    final active = PdfTabManager.instance.activeFile;
    if (active != null) {
      final state = _tabKeys[active.path]?.currentState;
      if (state != null) {
        _activeCurrentPage = state.currentPage;
        _activePagesCount = state.pagesCount;
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
    if (mounted && (_activeCurrentPage != current || _activePagesCount != total)) {
      setState(() {
        _activeCurrentPage = current;
        _activePagesCount = total;
      });
    }
  }

  void _openThumbnailsSidebar() {
    final activeFile = PdfTabManager.instance.activeFile;
    if (activeFile == null) return;
    final activeState = _tabKeys[activeFile.path]?.currentState;
    final totalPages = activeState?.pagesCount ?? _activePagesCount;
    final currentPage = activeState?.currentPage ?? _activeCurrentPage;

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
                setState(() {
                  _activeCurrentPage = pageNumber;
                });
                Navigator.of(dialogContext).pop();
              },
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(curved),
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
    } else {
      setState(() {});
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
          return; // User canceled exit
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
      _activatedTabPaths.add(activeFile.path);
    }
    final currentPaths = tabs.map((t) => t.path).toSet();
    _tabKeys.removeWhere((k, _) => !currentPaths.contains(k));
    _activatedTabPaths.removeWhere((p) => !currentPaths.contains(p));

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

            // Page Thumbnails Capsule (shows current page and total pages)
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
                      Text(
                        '$_activeCurrentPage / $_activePagesCount',
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
                      isActive: i == activeIdx,
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
  final bool isActive;
  final VoidCallback? onDirtyChanged;
  final void Function(int currentPage, int totalPages)? onPageInfoChanged;

  const PdfTabContent({
    super.key,
    required this.file,
    this.isActive = true,
    this.onDirtyChanged,
    this.onPageInfoChanged,
  });

  @override
  State<PdfTabContent> createState() => PdfTabContentState();
}

class PdfTabContentState extends State<PdfTabContent> {
  late PdfViewerController _pdfViewerController;
  late DrawingController _drawingController;
  GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey<SfPdfViewerState>();
  TransformationController? _transformationController;
  late File _pdfFile;

  static const _stylusChannel = MethodChannel('com.yin.pdfreor/stylus');

  bool _isLoading = true;
  String? _errorMessage;
  Timer? _loadingWatchdogTimer;
  Uint8List? _originalBaseBytes;
  bool _isSaving = false;

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

  int _currentPage = 1;
  int _pagesCount = 1;

  int get currentPage => _currentPage;
  int get pagesCount => _pagesCount;

  void jumpToPage(int pageNumber) {
    if (pageNumber >= 1 && pageNumber <= _pagesCount) {
      _pdfViewerController.jumpToPage(pageNumber);
      setState(() {
        _currentPage = pageNumber;
      });
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
  List<Size> _pageSizes = [];
  final List<Rect> _pageDocBounds = [];
  Rect? _textSelectionLocalRect;
  String? _selectedText;

  final List<Color> _annotationPalette = const [
    Color(0xFFFFEB3B), // Yellow (Highlighter)
    Color(0xFFFF9800), // Orange
    Color(0xFFF44336), // Red
    Color(0xFFE91E63), // Pink
    Color(0xFF9C27B0), // Purple
    Color(0xFF2196F3), // Blue
    Color(0xFF009688), // Teal
    Color(0xFF4CAF50), // Green
  ];

  bool get _isEraserActive => _isHardwareButtonPressed || _isPointerButtonPressed;

  bool get _hasUnsavedChanges {
    final hasPageChanges = _deletedZeroIndexedPages.isNotEmpty || _addedPagesCount > 0;
    if (hasPageChanges) return true;
    return _drawingController.hasUnsavedChanges;
  }

  ShapeType _activeShape = ShapeType.rectangle;
  Color _activeColor = const Color(0xFF212121); // Loaded from settings (for pen strokes & shapes)
  Color _highlightColor = const Color(0xFFFFEB3B); // Loaded from settings (for text highlight)
  Color _underlineColor = const Color(0xFFF44336); // Loaded from settings (for text underline)
  double _activeStrokeWidth = 3.0; // Loaded from settings
  double _activeFontSize = 16.0;
  Offset _toolbarPosition = const Offset(12, 100); // Loaded from settings
  bool _toolbarCollapsed = false; // Loaded from settings
  bool _isStylusDetected = false;
  bool _stylusOnlyMode = false;
  AppFontFamily _textBoxFont = AppFontFamily.sansSerif; // Loaded from settings

  void _saveSettings() {
    EditorSettingsService.saveSettings(EditorSettings(
      activeColor: _activeColor,
      highlightColor: _highlightColor,
      underlineColor: _underlineColor,
      activeStrokeWidth: _activeStrokeWidth,
      activeShape: _activeShape,
      toolbarPositionX: _toolbarPosition.dx,
      toolbarPositionY: _toolbarPosition.dy,
      toolbarCollapsed: _toolbarCollapsed,
      textBoxFont: _textBoxFont,
    ));
  }

  // Pending page manager operations
  List<int> _deletedZeroIndexedPages = [];
  int _addedPagesCount = 0;
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _pdfFile = File(widget.file.path);
    if (!_pdfFile.existsSync()) {
      _errorMessage = 'File does not exist: ${widget.file.path}';
      _isLoading = false;
    } else {
      _startLoadingWatchdog();
    }
    _pdfViewerController = PdfViewerController();
    _drawingController = DrawingController();
    _drawingController.addListener(_onDrawingControllerChanged);
    if (widget.isActive) {
      _stylusChannel.setMethodCallHandler(_handleStylusPlatformCall);
      _stylusChannel.invokeMethod<bool>('isStylusConnected').then((connected) {
        if (connected == true && mounted) {
          _onStylusDetected();
        }
      }).catchError((_) {});
    }

    // Restore last used color, stroke width, shape, toolbar position, and annotation colors
    EditorSettingsService.loadSettings().then((s) {
      if (mounted) {
        setState(() {
          _activeColor = s.activeColor;
          _highlightColor = s.highlightColor;
          _underlineColor = s.underlineColor;
          _activeStrokeWidth = s.activeStrokeWidth;
          _activeShape = s.activeShape;
          _toolbarPosition = Offset(s.toolbarPositionX, s.toolbarPositionY);
          _toolbarCollapsed = s.toolbarCollapsed;
          _textBoxFont = s.textBoxFont;
        });
        _pdfViewerController.annotationSettings.highlight.color = s.highlightColor;
        _pdfViewerController.annotationSettings.underline.color = s.underlineColor;
      }
    });
  }

  @override
  void didUpdateWidget(covariant PdfTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _stylusChannel.setMethodCallHandler(_handleStylusPlatformCall);
      _stylusChannel.invokeMethod<bool>('isStylusConnected').then((connected) {
        if (connected == true && mounted) {
          _onStylusDetected();
        }
      }).catchError((_) {});
    } else if (oldWidget.isActive && !widget.isActive) {
      _stylusChannel.setMethodCallHandler(null);
    }
  }

  @override
  void dispose() {
    _originalBaseBytes = null;
    _loadingWatchdogTimer?.cancel();
    _transformationController?.removeListener(_onTransformationChanged);
    if (widget.isActive) {
      _stylusChannel.setMethodCallHandler(null);
    }
    _drawingController.removeListener(_onDrawingControllerChanged);
    _drawingController.dispose();
    _pdfViewerController.dispose();
    super.dispose();
  }

  void _onDrawingControllerChanged() {
    if (mounted) {
      setState(() {});
      widget.onDirtyChanged?.call();
    }
  }

  void _onTransformationChanged() {
    // Dismiss annotation edit toolbar and text selection menu when scrolling or zooming
    if ((_selectedTextAnnotationId != null || _textSelectionLocalRect != null) && mounted) {
      setState(() {
        _selectedTextAnnotationId = null;
        _textSelectionLocalRect = null;
        _selectedText = null;
        _hasActiveTextSelection = false;
      });
    }
  }

  void _findAndAttachTransformationController([int retry = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _pdfViewerKey.currentContext;
      if (ctx is Element) {
        TransformationController? found;
        void visitor(Element el) {
          if (found != null) return;
          try {
            final dynamic w = el.widget;
            if (w.transformationController is TransformationController) {
              found = w.transformationController as TransformationController;
              return;
            }
          } catch (_) {}
          el.visitChildren(visitor);
        }
        ctx.visitChildren(visitor);

        if (found != null) {
          if (found != _transformationController) {
            _transformationController?.removeListener(_onTransformationChanged);
            _transformationController = found;
            _transformationController!.addListener(_onTransformationChanged);
            setState(() {});
          }
          return;
        }
      }

      if (retry < 6) {
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted) _findAndAttachTransformationController(retry + 1);
        });
      }
    });
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

  Future<void> _handleStylusPlatformCall(MethodCall call) async {
    if (!mounted) return;
    _onStylusDetected();

    if (call.method == 'onStylusButtonState') {
      final isPressed = call.arguments as bool? ?? false;
      setState(() {
        _isHardwareButtonPressed = isPressed;
        if (isPressed) {
          _activeTool = EditorTool.eraser;
        }
      });
      if (isPressed) {
        _drawingController.cancelActiveStroke();
      }
    } else if (call.method == 'onStylusButtonDown') {
      _lastButtonDownTime = DateTime.now();
      _toggleEraserMode();
    } else if (call.method == 'onStylusButtonUp') {
      // If no DOWN was received within 300ms, this device only sends UP
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
    _startLoadingWatchdog();
    setState(() {
      _errorMessage = null;
      _pdfViewerKey = GlobalKey<SfPdfViewerState>();
    });
  }

  void _onToolSelected(EditorTool tool) {
    setState(() {
      _activeTool = tool;
      if (tool == EditorTool.eraser) {
        _isHardwareButtonPressed = true;
      } else {
        _isHardwareButtonPressed = false;
      }
      _selectedTextAnnotationId = null;
      _textSelectionLocalRect = null;
      _selectedText = null;
    });
  }

  void _onColorSelected(Color color) {
    setState(() {
      _activeColor = color;
      if (_selectedShapeId != null) {
        final shape = _drawingController.shapes.cast<DrawnShape?>().firstWhere(
          (s) => s?.id == _selectedShapeId,
          orElse: () => null,
        );
        if (shape != null) {
          shape.color = color;
          _drawingController.updateDrawnShape(shape);
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
        }
      }
    });
    _saveSettings();
  }

  void _onStrokeWidthSelected(double width) {
    setState(() {
      _activeStrokeWidth = width;
      if (_selectedShapeId != null) {
        final shape = _drawingController.shapes.cast<DrawnShape?>().firstWhere(
          (s) => s?.id == _selectedShapeId,
          orElse: () => null,
        );
        if (shape != null) {
          shape.strokeWidth = width;
          _drawingController.updateDrawnShape(shape);
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
        }
      }
    });
    _saveSettings();
  }

  void _onFontSizeSelected(double fontSize) {
    setState(() {
      _activeFontSize = fontSize;
      if (_editingTextBoxId != null) {
        final tb = _drawingController.textBoxes.cast<DrawnTextBox?>().firstWhere(
          (t) => t?.id == _editingTextBoxId,
          orElse: () => null,
        );
        if (tb != null) {
          tb.fontSize = fontSize;
          _drawingController.updateTextBox(tb);
        }
      }
    });
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
        _stylusOnlyMode = true; // Auto-enable Palm Rejection
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
    });
  }

  BuildContext? _contextMenuDialogContext;

  void _showNonTextContextMenu(Offset screenPos, Offset docPos) {
    if (_hasActiveTextSelection || _isEraserActive || _isHardwareButtonPressed) return;
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
        const menuHeight = 195.0;
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
                      // Section 1: Draw Shape
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
                      // Section 2: Add TextBox
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
                              Icon(Icons.text_fields_rounded, size: 18, color: theme.colorScheme.primary),
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
                      // Section 3: Paste Option (Text or Image)
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
    // 1. Try to get image from clipboard via Android platform channel
    try {
      final imageBytes = await _stylusChannel.invokeMethod<Uint8List>('getClipboardImage');
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final codec = await ui.instantiateImageCodec(imageBytes);
        final frame = await codec.getNextFrame();
        final img = frame.image;
        final aspect = img.width / img.height;

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

    // 2. Try to get text from clipboard
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
        const SnackBar(content: Text('Clipboard is empty (no text or image found).'), duration: Duration(seconds: 2)),
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
        totalPages: _pagesCount,
        currentPage: _currentPage,
      ),
    );

    if (!mounted) return;

    if (result != null) {
      setState(() {
        _deletedZeroIndexedPages = List<int>.from(result.deletedZeroIndexedPages);
        _addedPagesCount = result.addedPagesCount;
      });

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

  sf.PdfColor _toPdfColor(Color c) {
    return sf.PdfColor(
      (c.r * 255.0).round().clamp(0, 255),
      (c.g * 255.0).round().clamp(0, 255),
      (c.b * 255.0).round().clamp(0, 255),
      (c.a * 255.0).round().clamp(0, 255),
    );
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
      // Cache original base bytes for this editing session so repeated saves never duplicate annotations
      _originalBaseBytes ??= await file.readAsBytes();

      final doc = sf.PdfDocument(inputBytes: Uint8List.fromList(_originalBaseBytes!));
      doc.compressionLevel = sf.PdfCompressionLevel.best;
      doc.fileStructure.crossReferenceType = sf.PdfCrossReferenceType.crossReferenceStream;

      final hasPageStructureChange = _deletedZeroIndexedPages.isNotEmpty || _addedPagesCount > 0;

      // 1. Delete pages in reverse order so indices remain stable
      _deletedZeroIndexedPages.sort((a, b) => b.compareTo(a));
      for (final pIdx in _deletedZeroIndexedPages) {
        if (pIdx >= 0 && pIdx < doc.pages.count) {
          doc.pages.removeAt(pIdx);
        }
      }

      // 2. Add blank pages at the end
      for (int i = 0; i < _addedPagesCount; i++) {
        doc.pages.add();
      }

      // 3. Render annotations, strokes, shapes, and text boxes onto the PDF pages in document coordinates
      final viewportWidth = _canvasSize.width > 0 ? _canvasSize.width : 400.0;
      const double pageSpacing = 4.0;

      // Build bounding rect for each page in document space
      final List<Rect> pageDocBounds = [];
      double currentY = 0.0;
      for (int i = 0; i < doc.pages.count; i++) {
        final pSize = doc.pages[i].size;
        final renderedH = viewportWidth * (pSize.height / pSize.width);
        pageDocBounds.add(Rect.fromLTWH(0, currentY, viewportWidth, renderedH));
        currentY += renderedH + pageSpacing;
      }

      int findPageIndex(double y) {
        for (int i = 0; i < pageDocBounds.length; i++) {
          final bounds = pageDocBounds[i];
          if (y <= bounds.bottom + pageSpacing / 2) {
            return i;
          }
        }
        return pageDocBounds.length - 1;
      }

      // Render text annotations (highlights, underlines, strikethroughs)
      for (final ta in _drawingController.textAnnotations) {
        final pageIdx = ta.pageNumber - 1;
        if (pageIdx < 0 || pageIdx >= doc.pages.count) continue;
        final page = doc.pages[pageIdx];
        final bounds = pageDocBounds[pageIdx];
        final scaleX = page.size.width / bounds.width;
        final scaleY = page.size.height / bounds.height;

        if (ta.type == TextAnnotationType.highlight) {
          page.graphics.save();
          page.graphics.setTransparency(0.35, mode: sf.PdfBlendMode.multiply);
          final brush = sf.PdfSolidBrush(_toPdfColor(ta.color));
          for (final r in ta.rects) {
            final pdfRect = Rect.fromLTWH(
              r.left * scaleX,
              (r.top - bounds.top) * scaleY,
              r.width * scaleX,
              r.height * scaleY,
            );
            page.graphics.drawRectangle(bounds: pdfRect, brush: brush);
          }
          page.graphics.restore();
        } else if (ta.type == TextAnnotationType.underline) {
          final pen = sf.PdfPen(_toPdfColor(ta.color), width: 1.5 * scaleX);
          for (final r in ta.rects) {
            final y = (r.bottom - bounds.top) * scaleY;
            page.graphics.drawLine(
              pen,
              Offset(r.left * scaleX, y),
              Offset(r.right * scaleX, y),
            );
          }
        } else if (ta.type == TextAnnotationType.strikethrough) {
          final pen = sf.PdfPen(_toPdfColor(ta.color), width: 1.5 * scaleX);
          for (final r in ta.rects) {
            final y = (r.center.dy - bounds.top) * scaleY;
            page.graphics.drawLine(
              pen,
              Offset(r.left * scaleX, y),
              Offset(r.right * scaleX, y),
            );
          }
        }
      }

      // Draw strokes efficiently using connected path and point deduplication
      for (final stroke in _drawingController.strokes) {
        if (stroke.points.isEmpty) continue;
        final pageIdx = findPageIndex(stroke.points.first.offset.dy);
        if (pageIdx < 0 || pageIdx >= doc.pages.count) continue;
        final page = doc.pages[pageIdx];
        final bounds = pageDocBounds[pageIdx];
        final scaleX = page.size.width / bounds.width;
        final scaleY = page.size.height / bounds.height;

        if (stroke.points.length == 1) {
          final pt = Offset(
            stroke.points.first.offset.dx * scaleX,
            (stroke.points.first.offset.dy - bounds.top) * scaleY,
          );
          final r = (stroke.strokeWidth * stroke.points.first.pressure / 2.0) * scaleX;
          final brush = sf.PdfSolidBrush(_toPdfColor(stroke.color));
          page.graphics.drawEllipse(Rect.fromCircle(center: pt, radius: r), brush: brush);
        } else {
          final List<Offset> docPoints = [];
          Offset? lastPt;
          for (final p in stroke.points) {
            final pt = Offset(
              p.offset.dx * scaleX,
              (p.offset.dy - bounds.top) * scaleY,
            );
            if (lastPt == null || (pt - lastPt).distanceSquared > 0.25) {
              docPoints.add(pt);
              lastPt = pt;
            }
          }
          if (docPoints.length < 2) {
            if (docPoints.isNotEmpty) {
              final r = (stroke.strokeWidth / 2.0) * scaleX;
              final brush = sf.PdfSolidBrush(_toPdfColor(stroke.color));
              page.graphics.drawEllipse(Rect.fromCircle(center: docPoints.first, radius: r), brush: brush);
            }
            continue;
          }

          final pen = sf.PdfPen(
            _toPdfColor(stroke.color),
            width: math.max(0.5, stroke.strokeWidth * scaleX),
          );
          pen.lineCap = sf.PdfLineCap.round;
          pen.lineJoin = sf.PdfLineJoin.round;

          final path = sf.PdfPath();
          for (int i = 0; i < docPoints.length - 1; i++) {
            path.addLine(docPoints[i], docPoints[i + 1]);
          }
          page.graphics.drawPath(path, pen: pen);
        }
      }

      // Draw shapes
      for (final shape in _drawingController.shapes) {
        final pageIdx = findPageIndex(shape.start.dy);
        if (pageIdx < 0 || pageIdx >= doc.pages.count) continue;
        final page = doc.pages[pageIdx];
        final bounds = pageDocBounds[pageIdx];
        final scaleX = page.size.width / bounds.width;
        final scaleY = page.size.height / bounds.height;

        final start = Offset(
          shape.start.dx * scaleX,
          (shape.start.dy - bounds.top) * scaleY,
        );
        final end = Offset(
          shape.end.dx * scaleX,
          (shape.end.dy - bounds.top) * scaleY,
        );
        final pen = sf.PdfPen(
          _toPdfColor(shape.color),
          width: shape.strokeWidth * scaleX,
        );

        switch (shape.type) {
          case ShapeType.rectangle:
            page.graphics.drawRectangle(bounds: Rect.fromPoints(start, end), pen: pen);
            break;

          case ShapeType.circle:
            page.graphics.drawEllipse(Rect.fromPoints(start, end), pen: pen);
            break;

          case ShapeType.line:
            page.graphics.drawLine(pen, start, end);
            break;

          case ShapeType.arrow:
            page.graphics.drawLine(pen, start, end);
            final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
            final arrowLength = math.max(shape.strokeWidth * 4.0 * scaleX, 12.0);
            const arrowAngle = math.pi / 6;

            final p1 = Offset(
              end.dx - arrowLength * math.cos(angle - arrowAngle),
              end.dy - arrowLength * math.sin(angle - arrowAngle),
            );
            final p2 = Offset(
              end.dx - arrowLength * math.cos(angle + arrowAngle),
              end.dy - arrowLength * math.sin(angle + arrowAngle),
            );

            page.graphics.drawLine(pen, end, p1);
            page.graphics.drawLine(pen, end, p2);
            break;
        }
      }

      // Draw text boxes (native vector text with auto-wrapping, zero image bloat)
      for (final tb in _drawingController.textBoxes) {
        if (tb.text.trim().isEmpty) continue;
        final pageIdx = findPageIndex(tb.position.dy);
        if (pageIdx < 0 || pageIdx >= doc.pages.count) continue;
        final page = doc.pages[pageIdx];
        final bounds = pageDocBounds[pageIdx];
        final scaleX = page.size.width / bounds.width;
        final scaleY = page.size.height / bounds.height;

        final pos = Offset(
          (tb.position.dx + 4) * scaleX,
          (tb.position.dy + 2 - bounds.top) * scaleY,
        );
        final tbWidth = (tb.width ?? 220.0) * scaleX;

        final isPureAscii = tb.text.codeUnits.every(
          (c) => (c >= 32 && c < 127) || c == 10 || c == 13 || c == 9,
        );

        // Vector font selection: lightweight standard PDF fonts with zero file bloat
        sf.PdfFont font;
        if (isPureAscii) {
          switch (_textBoxFont) {
            case AppFontFamily.sansSerif:
              font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, tb.fontSize * scaleX);
              break;
            case AppFontFamily.serif:
              font = sf.PdfStandardFont(sf.PdfFontFamily.timesRoman, tb.fontSize * scaleX);
              break;
            case AppFontFamily.monospace:
              font = sf.PdfStandardFont(sf.PdfFontFamily.courier, tb.fontSize * scaleX);
              break;
          }
        } else if (RegExp(r'[\u3040-\u30ff]').hasMatch(tb.text)) {
          font = sf.PdfCjkStandardFont(
            _textBoxFont == AppFontFamily.serif
                ? sf.PdfCjkFontFamily.heiseiMinchoW3
                : sf.PdfCjkFontFamily.heiseiKakuGothicW5,
            tb.fontSize * scaleX,
          );
        } else if (RegExp(r'[\uac00-\ud7af]').hasMatch(tb.text)) {
          font = sf.PdfCjkStandardFont(
            _textBoxFont == AppFontFamily.serif
                ? sf.PdfCjkFontFamily.hanyangSystemsShinMyeongJoMedium
                : sf.PdfCjkFontFamily.hanyangSystemsGothicMedium,
            tb.fontSize * scaleX,
          );
        } else {
          // Standard CJK font for Chinese - adds zero bytes of font data to PDF
          font = sf.PdfCjkStandardFont(
            sf.PdfCjkFontFamily.sinoTypeSongLight,
            tb.fontSize * scaleX,
          );
        }

        final brush = sf.PdfSolidBrush(_toPdfColor(tb.color));
        final format = sf.PdfStringFormat(
          wordWrap: sf.PdfWordWrapType.word,
        );

        try {
          page.graphics.drawString(
            tb.text,
            font,
            bounds: Rect.fromLTWH(
              pos.dx,
              pos.dy,
              tbWidth,
              1000 * scaleY,
            ),
            brush: brush,
            format: format,
          );
        } catch (_) {
          // Fallback only if font throws on an unsupported emoji or rare glyph
          const renderScale = 2.0;
          final textPainter = TextPainter(
            text: TextSpan(
              text: tb.text,
              style: TextStyle(
                color: tb.color,
                fontSize: tb.fontSize * scaleX * renderScale,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout(maxWidth: tbWidth * renderScale);

          final pWidth = math.max(1, textPainter.width.ceil());
          final pHeight = math.max(1, textPainter.height.ceil());

          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          textPainter.paint(canvas, Offset.zero);

          final picture = recorder.endRecording();
          final img = await picture.toImage(pWidth, pHeight);
          final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
          picture.dispose();
          img.dispose();

          if (byteData != null) {
            final pngBytes = byteData.buffer.asUint8List();
            final bmp = sf.PdfBitmap(pngBytes);
            page.graphics.drawImage(
              bmp,
              Rect.fromLTWH(
                pos.dx,
                pos.dy,
                pWidth / renderScale,
                pHeight / renderScale,
              ),
            );
          }
        }
      }

      // Draw pasted images
      for (final img in _drawingController.images) {
        final pageIdx = findPageIndex(img.position.dy);
        if (pageIdx < 0 || pageIdx >= doc.pages.count) continue;
        final page = doc.pages[pageIdx];
        final bounds = pageDocBounds[pageIdx];
        final scaleX = page.size.width / bounds.width;
        final scaleY = page.size.height / bounds.height;

        final pos = Offset(
          img.position.dx * scaleX,
          (img.position.dy - bounds.top) * scaleY,
        );
        final bmp = sf.PdfBitmap(img.imageBytes);
        page.graphics.drawImage(
          bmp,
          Rect.fromLTWH(pos.dx, pos.dy, img.width * scaleX, img.height * scaleY),
        );
      }

      // 4. Save directly into original file
      final finalBytes = doc.saveSync();
      doc.dispose();

      await file.writeAsBytes(finalBytes);

      // Invalidate thumbnail cache so the library screen updates
      PdfThumbnailService.instance.invalidate(file.path);

      _drawingController.markSaved();
      widget.onDirtyChanged?.call();

      if (hasPageStructureChange) {
        _originalBaseBytes = Uint8List.fromList(finalBytes);
        _deletedZeroIndexedPages.clear();
        _addedPagesCount = 0;
        _drawingController.clearAll();
        if (mounted) {
          await _reloadDocumentAfterSave();
        }
      }

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

  void _updatePageDocBounds() {
    if (_pageSizes.isEmpty) return;
    final viewportWidth = _canvasSize.width > 0 ? _canvasSize.width : 400.0;
    const double pageSpacing = 4.0;
    _pageDocBounds.clear();
    double currentY = 0.0;
    for (final pSize in _pageSizes) {
      final renderedH = viewportWidth * (pSize.height / pSize.width);
      _pageDocBounds.add(Rect.fromLTWH(0, currentY, viewportWidth, renderedH));
      currentY += renderedH + pageSpacing;
    }
  }

  void _createTextAnnotationFromSelection(TextAnnotationType type) {
    final selectedLines = _pdfViewerKey.currentState?.getSelectedTextLines();
    if (selectedLines == null || selectedLines.isEmpty) {
      _pdfViewerController.clearSelection();
      setState(() {
        _textSelectionLocalRect = null;
        _selectedText = null;
        _hasActiveTextSelection = false;
      });
      return;
    }

    _updatePageDocBounds();

    final Map<int, List<Rect>> pageRectsMap = {};
    for (final line in selectedLines) {
      final pageNum = line.pageNumber; // 1-based page number
      final pageIdx = pageNum - 1;
      if (pageIdx < 0 || pageIdx >= _pageDocBounds.length || pageIdx >= _pageSizes.length) {
        continue;
      }
      final pageBounds = _pageDocBounds[pageIdx];
      final originalSize = _pageSizes[pageIdx];
      final scaleX = pageBounds.width / originalSize.width;
      final scaleY = pageBounds.height / originalSize.height;

      final docRect = Rect.fromLTWH(
        line.bounds.left * scaleX,
        pageBounds.top + (line.bounds.top * scaleY),
        line.bounds.width * scaleX,
        line.bounds.height * scaleY,
      );
      pageRectsMap.putIfAbsent(pageNum, () => []).add(docRect);
    }

    Color color;
    if (type == TextAnnotationType.highlight) {
      color = _highlightColor;
    } else if (type == TextAnnotationType.underline) {
      color = _underlineColor;
    } else {
      color = const Color(0xFFF44336);
    }

    for (final entry in pageRectsMap.entries) {
      final annotation = DrawnTextAnnotation(
        type: type,
        rects: entry.value,
        color: color,
        pageNumber: entry.key,
      );
      _drawingController.addTextAnnotation(annotation);
    }

    _pdfViewerController.clearSelection();
    setState(() {
      _textSelectionLocalRect = null;
      _selectedText = null;
      _hasActiveTextSelection = false;
    });
    widget.onDirtyChanged?.call();
  }

  bool get hasUnsavedChanges => _hasUnsavedChanges;

  Future<bool> promptSaveIfDirty() => _promptSaveIfDirty();

  Future<bool> saveToOriginalFile({bool showFeedback = true}) =>
      _saveToOriginalFile(showFeedback: showFeedback);

  bool handleBackPress() {
    if (_selectedTextAnnotationId != null) {
      setState(() => _selectedTextAnnotationId = null);
      return true;
    }
    if (_textSelectionLocalRect != null) {
      _pdfViewerController.clearSelection();
      setState(() {
        _textSelectionLocalRect = null;
        _selectedText = null;
        _hasActiveTextSelection = false;
      });
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
      _pdfViewerController.clearSelection();
      setState(() => _hasActiveTextSelection = false);
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
                          setState(() {
                            _errorMessage = null;
                            _isLoading = true;
                            _pdfViewerKey = GlobalKey<SfPdfViewerState>();
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
                      _updatePageDocBounds();
                    }
                    return PassThroughStack(
                      fit: StackFit.expand,
                      children: [
                        // 1. PDF Viewer with native text selection in isolated render layer
                        RepaintBoundary(
                          child: SfPdfViewer.file(
                            _pdfFile,
                            key: _pdfViewerKey,
                            controller: _pdfViewerController,
                            canShowScrollHead: false,
                            canShowScrollStatus: false,
                            canShowPageLoadingIndicator: false,
                            canShowPaginationDialog: false,
                            canShowHyperlinkDialog: false,
                            canShowTextSelectionMenu: false,
                            enableDoubleTapZooming: true,
                            enableTextSelection: true,
                            pageSpacing: 4.0,
                          onTextSelectionChanged: (details) {
                            final hasSelection = details.selectedText != null &&
                                details.selectedText!.trim().isNotEmpty;
                            if (hasSelection && _contextMenuDialogContext != null) {
                              try {
                                Navigator.of(_contextMenuDialogContext!).pop();
                              } catch (_) {}
                              _contextMenuDialogContext = null;
                            }
                            if (hasSelection) {
                              _selectedTextAnnotationId = null;
                              _selectedShapeId = null;
                              _selectedStrokeId = null;
                              _editingTextBoxId = null;

                              final renderBox = context.findRenderObject() as RenderBox?;
                              if (renderBox != null && details.globalSelectedRegion != null) {
                                final topLeft = renderBox.globalToLocal(details.globalSelectedRegion!.topLeft);
                                final bottomRight = renderBox.globalToLocal(details.globalSelectedRegion!.bottomRight);
                                _textSelectionLocalRect = Rect.fromPoints(topLeft, bottomRight);
                              } else {
                                _textSelectionLocalRect = details.globalSelectedRegion;
                              }
                              _selectedText = details.selectedText;
                            } else {
                              _textSelectionLocalRect = null;
                              _selectedText = null;
                            }
                            setState(() {
                              _hasActiveTextSelection = hasSelection;
                            });
                          },
                          onDocumentLoaded: (details) {
                            _loadingWatchdogTimer?.cancel();
                            _pageSizes = List.generate(
                              details.document.pages.count,
                              (i) => Size(details.document.pages[i].size.width, details.document.pages[i].size.height),
                            );
                            _updatePageDocBounds();
                            if (mounted) {
                              setState(() {
                                _pagesCount = details.document.pages.count;
                                _isLoading = false;
                              });
                              _findAndAttachTransformationController();
                              widget.onPageInfoChanged?.call(_currentPage, _pagesCount);
                            }
                          },
                          onDocumentLoadFailed: (details) {
                            _loadingWatchdogTimer?.cancel();
                            if (mounted) {
                              setState(() {
                                _isLoading = false;
                                _errorMessage = details.description.isNotEmpty ? details.description : details.error;
                              });
                            }
                          },
                          onPageChanged: (details) {
                            _currentPage = details.newPageNumber;
                            widget.onPageInfoChanged?.call(_currentPage, _pagesCount);
                          },
                        ),
                      ),

                      // 2. High-performance Drawing Canvas (in isolated render layer)
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
                            widget.onDirtyChanged?.call();
                          },
                          onCancelOneShotShape: () => setState(() => _oneShotShape = null),
                          hasActiveTextSelection: _hasActiveTextSelection,
                          onNonTextLongPressed: _showNonTextContextMenu,
                          editingTextBoxId: _editingTextBoxId,
                          onEditingTextBoxChanged: (id) {
                            if (mounted) {
                              setState(() {
                                _editingTextBoxId = id;
                                if (id != null) {
                                  _selectedTextAnnotationId = null;
                                  _selectedShapeId = null;
                                  _selectedStrokeId = null;
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
                          onStylusDetected: _onStylusDetected,
                          onStylusDrawStarted: _onStylusDrawStarted,
                        ),
                      ),
                    ],
                  );
                },
              ),

                  // 3. Text Selection Floating Menu
                  if (_textSelectionLocalRect != null && _selectedText != null)
                    _buildTextSelectionMenu(),

                  // 3. Floating Tool Palette (With Green Dot Stylus Indicator & Adjacent Popups)
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

                  // 4. Loading Indicator Overlay
                  if (_isLoading)
                    Container(
                      color: Colors.black26,
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),

                  // 5. Unified Top Property Bar (for selected annotation, shape, or textbox)
                  _buildTopPropertyBar(),
                ],
              ),
            );
  }

  static const List<Color> _shapePalette = [
    Color(0xFF212121), // Black
    Color(0xFFD32F2F), // Red
    Color(0xFF1976D2), // Blue
    Color(0xFF388E3C), // Green
    Color(0xFFF57C00), // Orange
    Color(0xFF7B1FA2), // Purple
    Color(0xFF0097A7), // Cyan
    Color(0xFF757575), // Gray
  ];

  static const List<Color> _textPalette = [
    Color(0xFF212121), // Black
    Color(0xFFD32F2F), // Red
    Color(0xFF1976D2), // Blue
    Color(0xFF388E3C), // Green
    Color(0xFFF57C00), // Orange
    Color(0xFF7B1FA2), // Purple
    Color(0xFF0097A7), // Cyan
    Color(0xFF757575), // Gray
  ];

  Widget _buildTopPropertyBar() {
    final activeShape = _selectedShapeId != null
        ? _drawingController.shapes.cast<DrawnShape?>().firstWhere(
            (s) => s?.id == _selectedShapeId,
            orElse: () => null,
          )
        : null;
    final activeStroke = _selectedStrokeId != null
        ? _drawingController.strokes.cast<DrawingStroke?>().firstWhere(
            (s) => s?.id == _selectedStrokeId,
            orElse: () => null,
          )
        : null;
    final activeTextBox = _editingTextBoxId != null
        ? _drawingController.textBoxes.cast<DrawnTextBox?>().firstWhere(
            (t) => t?.id == _editingTextBoxId,
            orElse: () => null,
          )
        : null;
    final activeTextAnnotation = _selectedTextAnnotationId != null
        ? _drawingController.textAnnotations.cast<DrawnTextAnnotation?>().firstWhere(
            (ta) => ta?.id == _selectedTextAnnotationId,
            orElse: () => null,
          )
        : null;

    if (activeTextAnnotation == null &&
        activeShape == null &&
        activeStroke == null &&
        activeTextBox == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    Widget content;
    if (activeTextAnnotation != null) {
      content = _buildTextAnnotationBarContent(activeTextAnnotation, theme);
    } else if (activeShape != null) {
      content = _buildShapeBarContent(activeShape, theme);
    } else if (activeStroke != null) {
      content = _buildStrokeBarContent(activeStroke, theme);
    } else {
      content = _buildTextBoxBarContent(activeTextBox!, theme);
    }

    return Positioned(
      left: 12,
      right: 12,
      top: 10,
      child: Center(
        child: TapRegion(
          groupId: kEditableElementRegionGroup,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.surface,
            shadowColor: Colors.black45,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextAnnotationBarContent(DrawnTextAnnotation annotation, ThemeData theme) {
    IconData icon;
    String label;
    switch (annotation.type) {
      case TextAnnotationType.highlight:
        icon = Icons.border_color_rounded;
        label = 'Highlight';
        break;
      case TextAnnotationType.underline:
        icon = Icons.format_underlined_rounded;
        label = 'Underline';
        break;
      case TextAnnotationType.strikethrough:
        icon = Icons.format_strikethrough_rounded;
        label = 'Strikethrough';
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Type Icon and Label
        Icon(
          icon,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),

        // Palette Colors
        Row(
          mainAxisSize: MainAxisSize.min,
          children: _annotationPalette.map((color) {
            final isSelected =
                (annotation.color.toARGB32() & 0x00FFFFFF) == (color.toARGB32() & 0x00FFFFFF);
            return _buildColorDot(
              color: color,
              isSelected: isSelected,
              theme: theme,
              onTap: () {
                setState(() {
                  annotation.color = color;
                  _drawingController.updateTextAnnotation(annotation);
                  if (annotation.type == TextAnnotationType.highlight) {
                    _highlightColor = color;
                  } else if (annotation.type == TextAnnotationType.underline) {
                    _underlineColor = color;
                  }
                });
                _saveSettings();
                widget.onDirtyChanged?.call();
              },
            );
          }).toList(),
        ),

        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),

        // Delete Button
        _buildActionButton(
          icon: Icons.delete_outline_rounded,
          color: Colors.red,
          backgroundColor: const Color(0xFFFFEBEE),
          tooltip: 'Delete',
          onTap: () {
            setState(() {
              _drawingController.deleteTextAnnotation(annotation.id);
              _selectedTextAnnotationId = null;
            });
            widget.onDirtyChanged?.call();
          },
        ),

        const SizedBox(width: 6),

        // Done Button
        _buildActionButton(
          icon: Icons.check_rounded,
          color: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          tooltip: 'Done',
          onTap: () {
            setState(() {
              _selectedTextAnnotationId = null;
            });
          },
        ),
      ],
    );
  }

  Widget _buildTextSelectionMenu() {
    if (_textSelectionLocalRect == null) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    const menuHeight = 44.0;
    const idealMenuWidth = 360.0;
    final maxAllowedWidth = math.max(120.0, math.min(idealMenuWidth, screenWidth - 24.0));

    // Dynamic horizontal position: center on selected text, clamp strictly to screen bounds
    final selCenter = _textSelectionLocalRect!.center.dx;
    double left = selCenter - (maxAllowedWidth / 2);
    if (left + maxAllowedWidth > screenWidth - 12.0) {
      left = screenWidth - maxAllowedWidth - 12.0;
    }
    if (left < 12.0) {
      left = 12.0;
    }

    // Dynamic vertical position: place above if space permits, otherwise below, clamped safely
    double top = _textSelectionLocalRect!.top - menuHeight - 10.0;
    if (top < 56.0) {
      top = _textSelectionLocalRect!.bottom + 10.0;
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
                      _pdfViewerController.clearSelection();
                      setState(() {
                        _textSelectionLocalRect = null;
                        _selectedText = null;
                        _hasActiveTextSelection = false;
                      });
                    },
                  ),
                  _buildBarDivider(theme),
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

  Widget _buildShapeBarContent(DrawnShape shape, ThemeData theme) {
    IconData shapeIcon;
    String shapeName;
    switch (shape.type) {
      case ShapeType.rectangle:
        shapeIcon = Icons.rectangle_outlined;
        shapeName = 'Rectangle';
        break;
      case ShapeType.circle:
        shapeIcon = Icons.circle_outlined;
        shapeName = 'Circle';
        break;
      case ShapeType.line:
        shapeIcon = Icons.horizontal_rule_rounded;
        shapeName = 'Line';
        break;
      case ShapeType.arrow:
        shapeIcon = Icons.arrow_forward_rounded;
        shapeName = 'Arrow';
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Shape Icon and Label
        Icon(shapeIcon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          shapeName,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),

        // Stroke Width Stepper [-] X.X pt [+]
        _buildStepperButton(
          icon: Icons.remove,
          onTap: () {
            if (shape.strokeWidth > 1.0) {
              setState(() {
                shape.strokeWidth = math.max(1.0, shape.strokeWidth - 1.0);
              });
              _drawingController.updateDrawnShape(shape);
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${shape.strokeWidth.toStringAsFixed(1)} pt',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        _buildStepperButton(
          icon: Icons.add,
          onTap: () {
            if (shape.strokeWidth < 20.0) {
              setState(() {
                shape.strokeWidth = math.min(20.0, shape.strokeWidth + 1.0);
              });
              _drawingController.updateDrawnShape(shape);
            }
          },
        ),

        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),

        // Shape Stroke Color Palette
        Row(
          mainAxisSize: MainAxisSize.min,
          children: _shapePalette.map((color) {
            final isSelected =
                (shape.color.toARGB32() & 0x00FFFFFF) == (color.toARGB32() & 0x00FFFFFF);
            return _buildColorDot(
              color: color,
              isSelected: isSelected,
              theme: theme,
              onTap: () {
                setState(() {
                  shape.color = color;
                });
                _drawingController.updateDrawnShape(shape);
              },
            );
          }).toList(),
        ),

        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),

        // Delete Button
        _buildActionButton(
          icon: Icons.delete_outline_rounded,
          color: Colors.red,
          backgroundColor: const Color(0xFFFFEBEE),
          tooltip: 'Delete Shape',
          onTap: () {
            _drawingController.deleteDrawnShape(shape.id);
            setState(() {
              _selectedShapeId = null;
            });
          },
        ),

        const SizedBox(width: 6),

        // Done Button
        _buildActionButton(
          icon: Icons.check_rounded,
          color: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          tooltip: 'Done',
          onTap: () {
            setState(() {
              _selectedShapeId = null;
            });
          },
        ),
      ],
    );
  }

  Widget _buildStrokeBarContent(DrawingStroke stroke, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Stroke Icon and Label
        Icon(Icons.edit_rounded, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          'Stroke',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),

        // Stroke Width Stepper [-] X.X pt [+]
        _buildStepperButton(
          icon: Icons.remove,
          onTap: () {
            if (stroke.strokeWidth > 1.0) {
              setState(() {
                stroke.strokeWidth = math.max(1.0, stroke.strokeWidth - 1.0);
              });
              _drawingController.updateStroke(stroke);
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${stroke.strokeWidth.toStringAsFixed(1)} pt',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        _buildStepperButton(
          icon: Icons.add,
          onTap: () {
            if (stroke.strokeWidth < 30.0) {
              setState(() {
                stroke.strokeWidth = math.min(30.0, stroke.strokeWidth + 1.0);
              });
              _drawingController.updateStroke(stroke);
            }
          },
        ),

        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),

        // Palette Colors
        Row(
          mainAxisSize: MainAxisSize.min,
          children: _shapePalette.map((color) {
            final isSelected =
                (stroke.color.toARGB32() & 0x00FFFFFF) == (color.toARGB32() & 0x00FFFFFF);
            return _buildColorDot(
              color: color,
              isSelected: isSelected,
              theme: theme,
              onTap: () {
                setState(() {
                  stroke.color = color;
                });
                _drawingController.updateStroke(stroke);
              },
            );
          }).toList(),
        ),

        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),

        // Delete Button
        _buildActionButton(
          icon: Icons.delete_outline_rounded,
          color: Colors.red,
          backgroundColor: const Color(0xFFFFEBEE),
          tooltip: 'Delete Stroke',
          onTap: () {
            _drawingController.deleteStroke(stroke.id);
            setState(() {
              _selectedStrokeId = null;
            });
          },
        ),

        const SizedBox(width: 6),

        // Done Button
        _buildActionButton(
          icon: Icons.check_rounded,
          color: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          tooltip: 'Done',
          onTap: () {
            setState(() {
              _selectedStrokeId = null;
            });
          },
        ),
      ],
    );
  }

  Widget _buildTextBoxBarContent(DrawnTextBox tb, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Text Icon & Label
        Icon(Icons.text_fields_rounded, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          'Text',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),

        // Font Size Stepper [-] XX pt [+]
        _buildStepperButton(
          icon: Icons.remove,
          onTap: () {
            if (tb.fontSize > 8) {
              setState(() {
                tb.fontSize -= 2;
                _activeFontSize = tb.fontSize;
              });
              _drawingController.updateTextBox(tb);
              _saveSettings();
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${tb.fontSize.toInt()} pt',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        _buildStepperButton(
          icon: Icons.add,
          onTap: () {
            if (tb.fontSize < 72) {
              setState(() {
                tb.fontSize += 2;
                _activeFontSize = tb.fontSize;
              });
              _drawingController.updateTextBox(tb);
              _saveSettings();
            }
          },
        ),

        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),

        // Text Color Palette
        Row(
          mainAxisSize: MainAxisSize.min,
          children: _textPalette.map((color) {
            final isSelected =
                (tb.color.toARGB32() & 0x00FFFFFF) == (color.toARGB32() & 0x00FFFFFF);
            return _buildColorDot(
              color: color,
              isSelected: isSelected,
              theme: theme,
              onTap: () {
                setState(() {
                  tb.color = color;
                });
                _drawingController.updateTextBox(tb);
              },
            );
          }).toList(),
        ),

        const SizedBox(width: 8),
        _buildBarDivider(theme),
        const SizedBox(width: 8),

        // Delete Button
        _buildActionButton(
          icon: Icons.delete_outline_rounded,
          color: Colors.red,
          backgroundColor: const Color(0xFFFFEBEE),
          tooltip: 'Delete Text',
          onTap: () {
            _drawingController.deleteTextBox(tb.id);
            setState(() {
              _editingTextBoxId = null;
            });
          },
        ),

        const SizedBox(width: 6),

        // Done Button
        _buildActionButton(
          icon: Icons.check_rounded,
          color: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          tooltip: 'Done',
          onTap: () {
            setState(() {
              _editingTextBoxId = null;
            });
          },
        ),
      ],
    );
  }

  Widget _buildBarDivider(ThemeData theme) {
    return Container(
      height: 20,
      width: 1,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
        child: Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurface),
      ),
    );
  }

  Widget _buildColorDot({
    required Color color,
    required bool isSelected,
    required ThemeData theme,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? theme.colorScheme.primary : Colors.black26,
              width: isSelected ? 2.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  size: 14,
                  color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}

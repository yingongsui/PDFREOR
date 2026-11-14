import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import '../../controllers/drawing_controller.dart';
import '../../models/editor_models.dart';
import '../../models/pdf_file_info.dart';
import '../../services/annotation_persistence_codec.dart';
import '../../services/editor_settings_service.dart';
import '../../services/pdf_export_service.dart';
import '../../services/pdf_system_font_service.dart';
import '../../services/pdf_tab_manager.dart';
import '../../services/pdf_thumbnail_service.dart';
import '../../services/reading_progress_service.dart';
import '../../widgets/pass_through_stack.dart';
import '../../widgets/pdf_annotation_property_bar.dart';
import '../../widgets/pdf_editor_canvas.dart';
import '../../widgets/pdf_fast_scrollbar.dart';
import '../../widgets/pdf_floating_toolbar.dart';
import '../../widgets/pdf_page_manager_dialog.dart';
import 'pdf_viewer_delegates.dart';

part 'pdf_tab_content_sync.dart';
part 'pdf_tab_content_actions.dart';
part 'pdf_tab_content_menus.dart';
part 'pdf_tab_content_build.dart';

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


  late final pdfrx.PdfViewerController _pdfViewerController;
  late final TransformationController _transformationController;
  final GlobalKey<PdfFastScrollbarState> _fastScrollbarKey = GlobalKey<PdfFastScrollbarState>();
  int? _edgeTapPointerId;
  Offset? _edgeTapDownPos;
  Duration? _edgeTapDownTime;
  late DrawingController _drawingController;
  late File _pdfFile;
  pdfrx.PdfDocumentRef? _documentRef;
  int _reloadGeneration = 0;
  int _initGeneration = 0;
  bool _sessionEditableMode = false;
  bool _useInMemoryCleanBaseRef = false;
  PersistedAnnotationsBundle? _pendingRestoredBundle;

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
  int _initialPageNumber = 1;
  bool _isDocumentLoaded = false;
  int _currentPage = 1;
  int _pagesCount = 1;
  DateTime? _lastButtonDownTime;
  DateTime? _lastButtonToggleTime;

  int get currentPage => _currentPage;
  int get pagesCount => _pagesCount;

  void jumpToPage(int pageNumber) => _jumpToPage(pageNumber);

  void notifyStylusConnected() => _notifyStylusConnected();

  Future<void> handleStylusPlatformCall(MethodCall call) =>
      _handleStylusPlatformCall(call);

  BuildContext? _contextMenuDialogContext;

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
  List<Size> _pdfPageSizes = const [];
  final ValueNotifier<Rect?> _textSelectionLocalRectNotifier = ValueNotifier<Rect?>(null);
  Rect? _selectedUnionPdfrxDocRect;
  Map<int, List<Rect>> _selectedPageDocRects = const {};
  String? _selectedText;
  bool _isDraggingSelectionHandle = false;
  int _selectionSyncSerial = 0;
  double _lastReportedZoom = -1.0;
  Timer? _zoomSaveDebounceTimer;

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
    if (!_pdfFile.existsSync()) {
      _errorMessage = 'File does not exist: ${widget.file.path}';
      _isLoading = false;
    } else {
      _beginInitialDocumentOpen();
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
      _originalBaseBytes = null;
      _pendingRestoredBundle = null;
      _useInMemoryCleanBaseRef = false;
      _documentRef = null;
      _isDocumentLoaded = false;
      _errorMessage = null;
      _isLoading = true;
      _beginInitialDocumentOpen();
    }
    if (!oldWidget.initialStylusConnected && widget.initialStylusConnected) {
      _onStylusDetected();
    }
  }

  @override
  void dispose() {
    if (_zoomSaveDebounceTimer?.isActive == true && _lastReportedZoom >= 0.2) {
      ReadingProgressService.instance.saveLastZoom(
        widget.file.path,
        _lastReportedZoom,
        immediate: true,
      );
    }
    _zoomSaveDebounceTimer?.cancel();
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


  void _refresh([VoidCallback? fn]) {
    if (mounted) {
      setState(fn ?? () {});
    }
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
  Widget build(BuildContext context) => _buildTabContent(context);
}

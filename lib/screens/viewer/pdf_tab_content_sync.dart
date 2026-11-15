part of 'pdf_tab_content.dart';

extension _PdfTabContentSync on PdfTabContentState {
  void _disposeCleanBaseTempFile() {
    final tempFile = _cleanBaseTempFile;
    _cleanBaseTempFile = null;
    if (tempFile == null) return;
    try {
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    } catch (_) {
      // Best-effort cleanup for temporary clean-base PDF file.
    }
  }

  void _rebuildDocumentRef() {
    _disposeCleanBaseTempFile();
    if (_useInMemoryCleanBaseRef && _originalBaseBytes != null) {
      final bytes = _originalBaseBytes!;
      // On Windows, pdfrx_engine 0.4.7's in-memory custom reader (>1MB) has a
      // Win32 condition-variable race; load clean-base bytes via a temp file.
      if (Platform.isWindows && bytes.length > 1024 * 1024) {
        final tempFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'pdfreor_base_${DateTime.now().microsecondsSinceEpoch}_$_reloadGeneration.pdf',
        );
        tempFile.writeAsBytesSync(bytes, flush: true);
        _cleanBaseTempFile = tempFile;
        _documentRef = pdfrx.PdfDocumentRefFile(
          tempFile.path,
          useProgressiveLoading: false,
          key: pdfrx.PdfDocumentRefKey(_pdfFile.path, [_reloadGeneration, 'temp_clean']),
        );
      } else {
        _documentRef = pdfrx.PdfDocumentRefData(
          bytes,
          sourceName: _pdfFile.path,
          useProgressiveLoading: false,
          key: pdfrx.PdfDocumentRefKey(_pdfFile.path, [_reloadGeneration]),
        );
      }
    } else {
      _documentRef = pdfrx.PdfDocumentRefFile(
        _pdfFile.path,
        useProgressiveLoading: false,
        key: pdfrx.PdfDocumentRefKey(_pdfFile.path, [_reloadGeneration]),
      );
    }
  }

  void _disposeTextSearcher() {
    final searcher = _textSearcher;
    _textSearcher = null;
    if (searcher == null) return;
    searcher.removeListener(_onTextSearcherChanged);
    searcher.dispose();
  }

  void _ensureTextSearcher() {
    if (_textSearcher != null || !_pdfViewerController.isReady) return;
    final searcher = pdfrx.PdfTextSearcher(_pdfViewerController);
    searcher.addListener(_onTextSearcherChanged);
    _textSearcher = searcher;
  }

  void _onTextSearcherChanged() {
    if (mounted) {
      _refresh(() {});
    }
  }

  void _paintSearchMatches(
    ui.Canvas canvas,
    Rect pageRect,
    pdfrx.PdfPage page,
  ) {
    _textSearcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  void _onFindQueryChanged(String query, {bool forceRestart = false}) {
    _findQuery = query;
    _ensureTextSearcher();
    final searcher = _textSearcher;
    if (searcher == null) {
      _refresh(() {});
      return;
    }
    if (forceRestart) {
      searcher.resetTextSearch();
    }
    if (query.isEmpty) {
      searcher.resetTextSearch();
    } else {
      searcher.startTextSearch(
        query,
        caseInsensitive: !_findMatchCase,
        goToFirstMatch: true,
        searchImmediately: forceRestart,
      );
    }
    _refresh(() {});
  }

  void _toggleFindMatchCase() {
    _findMatchCase = !_findMatchCase;
    if (_findQuery.isNotEmpty) {
      _onFindQueryChanged(_findQuery, forceRestart: true);
    } else {
      _refresh(() {});
    }
  }

  Future<void> _findNextMatch() async {
    _ensureTextSearcher();
    final searcher = _textSearcher;
    if (searcher == null || _findQuery.isEmpty) return;
    if (searcher.matches.isEmpty) {
      if (!searcher.isSearching) {
        _onFindQueryChanged(_findQuery, forceRestart: true);
      }
      return;
    }
    final next = await searcher.goToNextMatch();
    if (next == -1 && searcher.matches.isNotEmpty) {
      await searcher.goToMatchOfIndex(0);
    }
    _refresh(() {});
  }

  Future<void> _findPrevMatch() async {
    _ensureTextSearcher();
    final searcher = _textSearcher;
    if (searcher == null || _findQuery.isEmpty) return;
    if (searcher.matches.isEmpty) return;
    final prev = await searcher.goToPrevMatch();
    if (prev == -1 && searcher.matches.isNotEmpty) {
      await searcher.goToMatchOfIndex(searcher.matches.length - 1);
    }
    _refresh(() {});
  }

  Future<void> _beginInitialDocumentOpen() async {
    final token = ++_initGeneration;
    try {
      final results = await Future.wait([
        EditorSettingsService.loadSettings(),
        _pdfFile.readAsBytes(),
      ]);
      if (!mounted || token != _initGeneration) return;

      final settings = results[0] as EditorSettings;
      final fileBytes = results[1] as Uint8List;
      final mode = settings.annotationPersistenceMode;

      final inspected = mode == AnnotationPersistenceMode.alwaysFlattened
          ? null
          : await PdfExportService.inspectPdfDocument(
              fileBytes,
              prepareCleanBaseForEditable: true,
            );
      if (!mounted || token != _initGeneration) return;

      final bool editableMode;
      switch (mode) {
        case AnnotationPersistenceMode.fileDefault:
          editableMode = inspected?.hasEditablePayload ?? false;
          break;
        case AnnotationPersistenceMode.alwaysEditable:
          editableMode = true;
          break;
        case AnnotationPersistenceMode.alwaysFlattened:
          editableMode = false;
          break;
      }

      _sessionEditableMode = editableMode;
      final hasRestorableBase =
          editableMode &&
          inspected != null &&
          inspected.hasEditablePayload &&
          inspected.cleanBaseBytes != null;
      _useInMemoryCleanBaseRef = hasRestorableBase;
      _originalBaseBytes = hasRestorableBase ? inspected.cleanBaseBytes : fileBytes;
      _pendingRestoredBundle = editableMode ? inspected?.bundle : null;

      _rebuildDocumentRef();
      _startLoadingWatchdog();
      _refresh(() {
        _errorMessage = null;
        _isLoading = true;
      });
    } catch (e) {
      if (!mounted || token != _initGeneration) return;
      _refresh(() {
        _isLoading = false;
        _errorMessage = 'Failed to open PDF file: $e';
      });
    }
  }

  void _startLoadingWatchdog() {
    _loadingWatchdogTimer?.cancel();
    _loadingWatchdogTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _isLoading) {
        _refresh(() {
          _isLoading = false;
        });
      }
    });
  }

  void _jumpToPage(int pageNumber) {
    if (pageNumber >= 1 && pageNumber <= _pagesCount) {
      if (_pdfViewerController.isReady) {
        _pdfViewerController.goToPage(
          pageNumber: pageNumber,
          anchor: pdfrx.PdfPageAnchor.top,
          duration: Duration.zero,
        );
      }
      _refresh(() {
        _currentPage = pageNumber;
      });
      ReadingProgressService.instance.saveLastPage(widget.file.path, _currentPage);
      widget.onPageInfoChanged?.call(_currentPage, _pagesCount);
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
    _refresh(() {});
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
        _zoomSaveDebounceTimer?.cancel();
        _zoomSaveDebounceTimer = Timer(const Duration(milliseconds: 220), () {
          if (mounted) {
            ReadingProgressService.instance.saveLastZoom(widget.file.path, zoom);
          }
        });
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
    _refresh(() {
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
        pageRectsMap[pageNum] = mergeLineRects(rawCanvasRects);
      }
    }

    if (unionPdfrxRect == null || pageRectsMap.isEmpty) {
      _resetSelectionOverlayState();
      return;
    }

    _textSelectionLocalRectNotifier.value = _isDraggingSelectionHandle
        ? null
        : _computeLocalRectFromPdfrxDocRect(unionPdfrxRect);
    _refresh(() {
      _selectedTextAnnotationId = null;
      _selectedShapeId = null;
      _selectedStrokeId = null;
      _selectedImageId = null;
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
      final target = PdfTabContentState.computeInitialViewportTarget(
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
    _pdfPageSizes = document.pages
        .map((p) => Size(p.width, p.height))
        .toList(growable: false);

    final pendingRestore = _pendingRestoredBundle;
    _pendingRestoredBundle = null;
    if (pendingRestore != null &&
        _sessionEditableMode &&
        pendingRestore.pageCount == totalPages) {
      final restored = pendingRestore.toModelLists(
        _pageDocBounds,
        _pdfPageSizes,
      );
      _drawingController.restorePersistedAnnotations(
        strokes: restored.strokes,
        shapes: restored.shapes,
        textBoxes: restored.textBoxes,
        images: restored.images,
        textAnnotations: restored.textAnnotations,
      );
      _notifyDirtyIfChanged();
    }
    _lastReportedZoom = controller.currentZoom;
    _isDocumentLoaded = true;
    _ensureTextSearcher();
    if (_isFindBarVisible && _findQuery.isNotEmpty) {
      _onFindQueryChanged(_findQuery, forceRestart: true);
    }
    final actualPage = controller.pageNumber ?? targetPage;
    _refresh(() {
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
      _refresh(() {
        _isLoading = false;
        _errorMessage = err?.toString() ?? 'Failed to open PDF document.';
      });
    } else if (_isDocumentLoaded && _isLoading) {
      _loadingWatchdogTimer?.cancel();
      _refresh(() {
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
    if (_oneShotShape != null || _isEraserActive || _activeTool != EditorTool.select) {
      return;
    }

    if (link.url != null) {
      final urlString = link.url.toString();
      final success = await PlatformBridge.openUrl(urlString);
      if (!success) {
        await Clipboard.setData(ClipboardData(text: urlString));
        _showViewerSnackBar('Link copied to clipboard');
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
          _refresh(() {
            _selectedTextAnnotationId = null;
            _selectedShapeId = null;
            _selectedStrokeId = null;
            _selectedImageId = null;
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
}

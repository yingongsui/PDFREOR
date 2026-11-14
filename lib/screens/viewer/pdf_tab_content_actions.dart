part of 'pdf_tab_content.dart';

extension _PdfTabContentActions on PdfTabContentState {
  void _toggleEraserMode() {
    final now = DateTime.now();
    if (_lastButtonToggleTime != null &&
        now.difference(_lastButtonToggleTime!).inMilliseconds <= 200) {
      return;
    }
    _lastButtonToggleTime = now;
    _refresh(() {
      final nextIsEraser = !_isEraserActive;
      _isHardwareButtonPressed = nextIsEraser;
      _activeTool = nextIsEraser ? EditorTool.eraser : EditorTool.pen;
    });
    _drawingController.cancelActiveStroke();
  }

  Future<void> _handleStylusPlatformCall(MethodCall call) async {
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
      _refresh(() {
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
    _pdfPageSizes = const [];
    _rebuildDocumentRef();
    _startLoadingWatchdog();
    _refresh(() {
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
    _refresh(() {
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
      _refresh(() {});
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
      _refresh(() {});
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
      _refresh(() {});
    }
  }

  void _onShapeSelected(ShapeType shape) {
    _refresh(() {
      _activeShape = shape;
    });
    _saveSettings();
  }

  void _onStylusDetected() {
    final shouldSwitchToPen =
        !_isStylusDetected && _activeTool == EditorTool.select;
    if (!_isStylusDetected || !_stylusOnlyMode || shouldSwitchToPen) {
      _refresh(() {
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
      _refresh(() {
        _activeTool = EditorTool.pen;
      });
    }
  }

  void _addInlineTextBox(Offset position) {
    final newId = nextAnnotationId();
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
    _refresh(() {
      _editingTextBoxId = newId;
      _activeTool = EditorTool.select;
    });
  }

  void _addInlineLatexBox(Offset position) {
    final newId = nextAnnotationId();
    final newBox = DrawnTextBox(
      id: newId,
      text: '',
      position: position,
      color: _activeColor,
      fontSize: math.max(18.0, _activeFontSize),
      pageNumber: _currentPage,
      width: 180.0,
      isLatex: true,
    );
    _drawingController.addTextBox(newBox);
    _refresh(() {
      _editingTextBoxId = newId;
      _activeTool = EditorTool.select;
    });
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
      _refresh(() {
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
      _refresh(() {
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
        pdfPageSizes: _pdfPageSizes.isNotEmpty ? _pdfPageSizes : null,
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

}

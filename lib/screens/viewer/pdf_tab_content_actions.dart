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

  void _showViewerSnackBar(
    String message, {
    Color? backgroundColor,
    IconData? icon,
    Duration duration = const Duration(seconds: 2),
    bool floating = false,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(message),
                ],
              )
            : Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: floating ? SnackBarBehavior.floating : null,
      ),
    );
  }

  void _onColorSelected(Color color) {
    bool controllerNotified = false;
    _activeColor = color;
    final shape = _drawingController.findShapeById(_selectedShapeId);
    if (shape != null) {
      shape.color = color;
      _drawingController.updateDrawnShape(shape);
      controllerNotified = true;
    }
    final stroke = _drawingController.findStrokeById(_selectedStrokeId);
    if (stroke != null) {
      stroke.color = color;
      _drawingController.updateStroke(stroke);
      controllerNotified = true;
    }
    final tb = _drawingController.findTextBoxById(_editingTextBoxId);
    if (tb != null) {
      tb.color = color;
      _drawingController.updateTextBox(tb);
      controllerNotified = true;
    }
    if (!controllerNotified) {
      _refresh(() {});
    }
    _saveSettings();
  }

  void _onStrokeWidthSelected(double width) {
    bool controllerNotified = false;
    _activeStrokeWidth = width;
    final shape = _drawingController.findShapeById(_selectedShapeId);
    if (shape != null) {
      shape.strokeWidth = width;
      _drawingController.updateDrawnShape(shape);
      controllerNotified = true;
    }
    final stroke = _drawingController.findStrokeById(_selectedStrokeId);
    if (stroke != null) {
      stroke.strokeWidth = width;
      _drawingController.updateStroke(stroke);
      controllerNotified = true;
    }
    if (!controllerNotified) {
      _refresh(() {});
    }
    _saveSettings();
  }

  void _onFontSizeSelected(double fontSize) {
    bool controllerNotified = false;
    _activeFontSize = fontSize;
    final tb = _drawingController.findTextBoxById(_editingTextBoxId);
    if (tb != null) {
      tb.fontSize = fontSize;
      _drawingController.updateTextBox(tb);
      controllerNotified = true;
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

  void _addInlineBox(Offset position, {bool isLatex = false}) {
    final newId = nextAnnotationId();
    final newBox = DrawnTextBox(
      id: newId,
      text: '',
      position: position,
      color: _activeColor,
      fontSize: isLatex ? math.max(18.0, _activeFontSize) : _activeFontSize,
      pageNumber: _currentPage,
      width: isLatex ? 180.0 : 220.0,
      isLatex: isLatex,
    );
    _drawingController.addTextBox(newBox);
    _refresh(() {
      _editingTextBoxId = newId;
      _activeTool = EditorTool.select;
    });
  }

  void _addInlineTextBox(Offset position) => _addInlineBox(position);

  void _addInlineLatexBox(Offset position) => _addInlineBox(position, isLatex: true);


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
        _showViewerSnackBar(
          'Page changes staged (Deleted: ${_deletedZeroIndexedPages.length}, Added: $_addedPagesCount). Tap Save to apply to file.',
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  Future<double> _preparePdfExportViewportWidth() async {
    if (_editingTextBoxId != null && mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
      _refresh(() {
        _editingTextBoxId = null;
      });
      await WidgetsBinding.instance.endOfFrame;
    }
    _originalBaseBytes ??= await File(widget.file.path).readAsBytes();
    _syncDocumentLayoutFromController();
    return _baseNormalizedWidth ?? (_canvasSize.width > 0 ? _canvasSize.width : 400.0);
  }

  Future<bool> _saveToOriginalFile({
    bool showFeedback = true,
    bool? overrideEditableMode,
  }) async {
    if (_isSaving) return false;
    _isSaving = true;
    final targetEditableMode = overrideEditableMode ?? _sessionEditableMode;

    try {
      final file = File(widget.file.path);
      final hasPageStructureChange = _deletedZeroIndexedPages.isNotEmpty || _addedPagesCount > 0;
      final viewportWidth = await _preparePdfExportViewportWidth();

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
        embedEditableData: targetEditableMode,
      );

      // Invalidate thumbnail cache and refresh open tab file metadata
      PdfThumbnailService.instance.invalidate(file.path);
      try {
        PdfTabManager.instance.renameTab(file.path, PdfFileInfo.fromFile(file));
      } catch (_) {}

      _sessionEditableMode = targetEditableMode;
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

        _deletedZeroIndexedPages.clear();
        _addedPagesCount = 0;

        if (_sessionEditableMode) {
          final reinspected = await PdfExportService.inspectPdfDocument(
            finalBytes,
            prepareCleanBaseForEditable: true,
          );
          if (reinspected.hasEditablePayload && reinspected.cleanBaseBytes != null) {
            _originalBaseBytes = reinspected.cleanBaseBytes;
            _pendingRestoredBundle = reinspected.bundle;
            _useInMemoryCleanBaseRef = true;
          } else {
            _originalBaseBytes = finalBytes;
            _pendingRestoredBundle = null;
            _useInMemoryCleanBaseRef = false;
          }
        } else {
          _originalBaseBytes = finalBytes;
          _pendingRestoredBundle = null;
          _useInMemoryCleanBaseRef = false;
        }

        _drawingController.clearAll();
        if (mounted) {
          await _reloadDocumentAfterSave();
        }
      }

      _notifyDirtyIfChanged();

      if (showFeedback) {
        _showViewerSnackBar(
          targetEditableMode
              ? 'Saved as Advanced (Editable)!'
              : 'Saved as Standard (Flattened)!',
          backgroundColor: Colors.green,
          icon: Icons.check_circle_rounded,
          floating: true,
        );
      }
      return true;
    } catch (e) {
      if (showFeedback) {
        _showViewerSnackBar(
          'Failed to save file: $e',
          backgroundColor: Colors.red,
          floating: true,
        );
      }
      return false;
    } finally {
      _isSaving = false;
    }
  }

  Future<void> _promptSaveMethodDialog() async {
    if (_isSaving || !mounted || !context.mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final isAdv = _sessionEditableMode;
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.save_as_rounded, size: 22),
              SizedBox(width: 8),
              Text('Save Options'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose how to save this document:',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _SaveOptionTile(
                icon: Icons.edit_note_rounded,
                title: 'Save — Advanced',
                subtitle: 'Keep annotations editable on future reopen.',
                badge: isAdv ? 'Current' : null,
                onTap: () => Navigator.pop(dialogContext, 'advanced'),
              ),
              const SizedBox(height: 8),
              _SaveOptionTile(
                icon: Icons.layers_clear_rounded,
                title: 'Save — Standard',
                subtitle: 'Flatten annotations permanently into standard PDF.',
                badge: !isAdv ? 'Current' : null,
                onTap: () => Navigator.pop(dialogContext, 'standard'),
              ),
              const SizedBox(height: 8),
              _SaveOptionTile(
                icon: Icons.file_download_outlined,
                title: 'Export Standard Copy',
                subtitle: 'Save a separate flattened PDF without altering this file.',
                onTap: () => Navigator.pop(dialogContext, 'export_copy'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (!mounted || choice == null) return;
    if (choice == 'advanced') {
      await _saveToOriginalFile(showFeedback: true, overrideEditableMode: true);
    } else if (choice == 'standard') {
      await _saveToOriginalFile(showFeedback: true, overrideEditableMode: false);
    } else if (choice == 'export_copy') {
      await _exportFlattenedCopy();
    }
  }

  Future<void> _exportFlattenedCopy() async {
    if (_isSaving) return;
    _isSaving = true;

    try {
      final viewportWidth = await _preparePdfExportViewportWidth();

      final flattenedBytes = await PdfExportService.buildExportBytes(
        baseBytes: _originalBaseBytes!,
        drawingController: _drawingController,
        viewportWidth: viewportWidth,
        textBoxFont: _textBoxFont,
        deletedZeroIndexedPages: _deletedZeroIndexedPages,
        addedPagesCount: _addedPagesCount,
        pageDocBounds: _pageDocBounds.isNotEmpty ? _pageDocBounds : null,
        pdfPageSizes: _pdfPageSizes.isNotEmpty ? _pdfPageSizes : null,
        embedEditableData: false,
      );

      final rawName = widget.file.name;
      final baseName = rawName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      final suggestedName = '${baseName}_flattened.pdf';

      final savedUri = await FilePicker.saveFile(
        dialogTitle: 'Export Standard PDF (Flattened)',
        fileName: suggestedName,
        bytes: flattenedBytes,
      );
      if (savedUri == null) return;

      if (!Platform.isAndroid && !Platform.isIOS) {
        await File.fromUri(savedUri).writeAsBytes(flattenedBytes, flush: true);
      }

      _showViewerSnackBar(
        'Standard flattened PDF exported!',
        backgroundColor: Colors.green,
        icon: Icons.check_circle_rounded,
        floating: true,
      );
    } catch (e) {
      _showViewerSnackBar(
        'Failed to export flattened PDF: $e',
        backgroundColor: Colors.red,
        floating: true,
      );
    } finally {
      _isSaving = false;
    }
  }

  Future<void> _openExternal() async {
    try {
      final result = await OpenFilex.open(widget.file.path);
      if (result.type != ResultType.done) {
        _showViewerSnackBar('Cannot open external app: ${result.message}');
      }
    } catch (e) {
      _showViewerSnackBar('Error: $e');
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

class _SaveOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _SaveOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: badge != null
                ? theme.colorScheme.primary.withValues(alpha: 0.6)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

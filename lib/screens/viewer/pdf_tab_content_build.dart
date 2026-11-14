part of 'pdf_tab_content.dart';

extension _PdfTabContentBuild on PdfTabContentState {
  Widget _buildTabContent(BuildContext context) {
    final theme = Theme.of(context);

    final selectedShape = _drawingController.findShapeById(_selectedShapeId);
    final selectedStroke = _drawingController.findStrokeById(_selectedStrokeId);
    final editingTextBox = _drawingController.findTextBoxById(_editingTextBoxId);
    final selectedTextAnnotation =
        _drawingController.findTextAnnotationById(_selectedTextAnnotationId);

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
                          _refresh(() {
                            _errorMessage = null;
                            _isLoading = true;
                          });
                          if (_documentRef == null) {
                            _beginInitialDocumentOpen();
                          } else {
                            _rebuildDocumentRef();
                            _startLoadingWatchdog();
                          }
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
              if (isStylusPointer(event)) {
                _onStylusDetected();
              }
            },
            onPointerDown: (event) {
              if (isStylusPointer(event)) {
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
                    return Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) {
                        final nearHorizontalEdge = event.localPosition.dx >= newSize.width - 42.0 ||
                            event.localPosition.dx <= 28.0;
                        if (!isStylusPointer(event) && nearHorizontalEdge) {
                          _edgeTapPointerId = event.pointer;
                          _edgeTapDownPos = event.localPosition;
                          _edgeTapDownTime = event.timeStamp;
                        }
                      },
                      onPointerUp: (event) {
                        if (event.pointer == _edgeTapPointerId) {
                          final downPos = _edgeTapDownPos;
                          final downTime = _edgeTapDownTime;
                          _edgeTapPointerId = null;
                          if (downPos != null &&
                              downTime != null &&
                              (event.localPosition - downPos).distance <= 10.0 &&
                              (event.timeStamp - downTime) <= const Duration(milliseconds: 260)) {
                            _fastScrollbarKey.currentState?.reveal(withHaptic: true);
                          }
                        }
                      },
                      onPointerCancel: (event) {
                        if (event.pointer == _edgeTapPointerId) {
                          _edgeTapPointerId = null;
                        }
                      },
                      child: PassThroughStack(
                        fit: StackFit.expand,
                        children: [
                        RepaintBoundary(
                          child: _documentRef == null
                              ? const SizedBox.shrink()
                              : pdfrx.PdfViewer(
                                  _documentRef!,
                                  controller: _pdfViewerController,
                            fontManager: PdfSystemFontService.instance.fontManager,
                            initialPageNumber: _initialPageNumber,
                            params: pdfrx.PdfViewerParams(
                              margin: 0.0,
                              layoutPages: PdfTabContentState._layoutVerticalPages,
                              buildContextMenu: suppressBuiltInContextMenu,
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
                              sizeDelegateProvider: const DeferredInitSmartSizeDelegateProvider(
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
                              _refresh(() {
                                _oneShotShape = null;
                                if (_drawingController.shapes.isNotEmpty) {
                                  _selectedShapeId = _drawingController.shapes.last.id;
                                  _selectedStrokeId = null;
                                  _selectedTextAnnotationId = null;
                                }
                              });
                              _notifyDirtyIfChanged();
                            },
                            onCancelOneShotShape: () => _refresh(() => _oneShotShape = null),
                            hasActiveTextSelection: _hasActiveTextSelection,
                            editingTextBoxId: _editingTextBoxId,
                            onEditingTextBoxChanged: (id) {
                              if (mounted) {
                                _refresh(() {
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
                                _refresh(() {
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
                                _refresh(() {
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
                                _refresh(() {
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
                                _refresh(() {
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
                              _refresh(() {
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
                      ),
                    );
                  },
                ),
                if (_isDocumentLoaded)
                  Positioned.fill(
                    child: PdfFastScrollbar(
                      key: _fastScrollbarKey,
                      controller: _pdfViewerController,
                      onPageScrubbed: _onPdfPageChanged,
                      bottomPadding: (selectedTextAnnotation != null ||
                              selectedShape != null ||
                              selectedStroke != null ||
                              editingTextBox != null)
                          ? 76.0
                          : 12.0,
                    ),
                  ),
                if (_selectedText != null)
                  ValueListenableBuilder<Rect?>(
                    valueListenable: _textSelectionLocalRectNotifier,
                    builder: (context, localRect, _) {
                      if (localRect == null) return const SizedBox.shrink();
                      return PdfTextSelectionMenu(
                        localRect: localRect,
                        canvasSize: _canvasSize,
                        highlightColor: _highlightColor,
                        underlineColor: _underlineColor,
                        onCopy: () async {
                          await Clipboard.setData(ClipboardData(text: _selectedText ?? ''));
                          _clearPdfTextSelection();
                        },
                        onHighlight: () => _createTextAnnotationFromSelection(TextAnnotationType.highlight),
                        onUnderline: () => _createTextAnnotationFromSelection(TextAnnotationType.underline),
                        onStrikethrough: () => _createTextAnnotationFromSelection(TextAnnotationType.strikethrough),
                      );
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
                  onStylusOnlyModeToggled: (mode) => _refresh(() => _stylusOnlyMode = mode),
                  onUndo: () => _drawingController.undo(),
                  onManagePages: _openPageManager,
                  onSave: () => _saveToOriginalFile(showFeedback: true),
                  onSaveOptions: _promptSaveMethodDialog,
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
                    _refresh(() => _selectedTextAnnotationId = null);
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
                    _refresh(() => _selectedShapeId = null);
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
                    _refresh(() => _selectedStrokeId = null);
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
                    _refresh(() {
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

}

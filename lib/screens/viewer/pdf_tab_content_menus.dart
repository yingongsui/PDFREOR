part of 'pdf_tab_content.dart';

extension _PdfTabContentMenus on PdfTabContentState {
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
        const menuWidth = 240.0;
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
                          for (final type in kOrderedShapeTypes)
                            _buildShapeQuickAction(dialogContext, type),
                        ],
                      ),
                      _buildContextMenuAction(
                        dialogContext,
                        icon: Icons.title_rounded,
                        label: 'Add TextBox',
                        onTap: () => _addInlineTextBox(docPos),
                      ),
                      _buildContextMenuAction(
                        dialogContext,
                        icon: Icons.functions_rounded,
                        label: 'Add LaTeX Formula',
                        onTap: () => _addInlineLatexBox(docPos),
                      ),
                      _buildContextMenuAction(
                        dialogContext,
                        icon: Icons.content_paste_rounded,
                        label: 'Paste (Text or Image)',
                        onTap: () => _handlePaste(docPos),
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
      final imageBytes = await PdfTabContentState._stylusChannel.invokeMethod<Uint8List>('getClipboardImage');
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
        _showViewerSnackBar('Image pasted from clipboard!');
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
        _showViewerSnackBar('Text pasted from clipboard!');
        return;
      }
    } catch (_) {}

    _showViewerSnackBar('Clipboard is empty (no text or image found).');
  }

  Widget _buildContextMenuAction(
    BuildContext dialogContext, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Navigator.pop(dialogContext);
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShapeQuickAction(BuildContext dialogContext, ShapeType shape) {
    return Tooltip(
      message: shape.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.pop(dialogContext);
          _refresh(() {
            _oneShotShape = shape;
          });
        },
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          child: Icon(shape.icon, size: 20),
        ),
      ),
    );
  }

}

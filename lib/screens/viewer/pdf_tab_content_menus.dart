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
                          _buildShapeQuickAction(dialogContext, ShapeType.rectangle, Icons.rectangle_outlined, 'Rectangle'),
                          _buildShapeQuickAction(dialogContext, ShapeType.roundedRectangle, Icons.rounded_corner_rounded, 'Rounded Rect'),
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
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }

}

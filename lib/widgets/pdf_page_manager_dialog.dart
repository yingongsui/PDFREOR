import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/pdf_file_info.dart';
import '../services/pdf_thumbnail_service.dart';

class PageManagerResult {
  final List<int> deletedZeroIndexedPages;
  final int addedPagesCount;

  PageManagerResult({
    required this.deletedZeroIndexedPages,
    required this.addedPagesCount,
  });
}

class PdfPageManagerDialog extends StatefulWidget {
  final PdfFileInfo? file;
  final int totalPages;
  final int currentPage;

  const PdfPageManagerDialog({
    super.key,
    this.file,
    required this.totalPages,
    required this.currentPage,
  });

  @override
  State<PdfPageManagerDialog> createState() => _PdfPageManagerDialogState();
}

class _PdfPageManagerDialogState extends State<PdfPageManagerDialog> {
  late List<int> _currentPages; // list of 1-based original page numbers (negative = newly added blank)
  int _addedCount = 0;

  @override
  void initState() {
    super.initState();
    _currentPages = List.generate(widget.totalPages, (i) => i + 1);
  }

  void _addBlankPage() {
    setState(() {
      _addedCount++;
      _currentPages.add(-_addedCount);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Blank page added at the end')),
    );
  }

  void _deletePage(int index) {
    if (_currentPages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete the last remaining page')),
      );
      return;
    }

    final pageLabel = _currentPages[index] > 0
        ? 'Page ${_currentPages[index]}'
        : 'Newly Added Blank Page';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Page?'),
        content: Text('Are you sure you want to delete $pageLabel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _currentPages.removeAt(index);
              });
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_stories_rounded),
          const SizedBox(width: 8),
          const Text('Manage Pages'),
          const Spacer(),
          IconButton.filledTonal(
            icon: const Icon(Icons.add),
            tooltip: 'Add Blank Page',
            onPressed: _addBlankPage,
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total Pages: ${_currentPages.length} (Original: ${widget.totalPages})',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.72,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _currentPages.length,
                itemBuilder: (context, index) {
                  final pageNum = _currentPages[index];
                  final isNew = pageNum < 0;
                  final isCurrent = pageNum == widget.currentPage;

                  return _PageManagerGridTile(
                    key: ValueKey('pm_page_$pageNum'),
                    file: widget.file,
                    pageNum: pageNum,
                    isNew: isNew,
                    isCurrent: isCurrent,
                    onDelete: () => _deletePage(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final remainingOriginals = _currentPages.where((p) => p > 0).toSet();
            final deletedOriginalZeroIndexed = <int>[];
            for (int i = 0; i < widget.totalPages; i++) {
              if (!remainingOriginals.contains(i + 1)) {
                deletedOriginalZeroIndexed.add(i);
              }
            }
            final newlyAdded = _currentPages.where((p) => p < 0).length;

            Navigator.pop(
              context,
              PageManagerResult(
                deletedZeroIndexedPages: deletedOriginalZeroIndexed,
                addedPagesCount: newlyAdded,
              ),
            );
          },
          child: const Text('Apply Changes'),
        ),
      ],
    );
  }
}

class _PageManagerGridTile extends StatefulWidget {
  final PdfFileInfo? file;
  final int pageNum;
  final bool isNew;
  final bool isCurrent;
  final VoidCallback onDelete;

  const _PageManagerGridTile({
    super.key,
    required this.file,
    required this.pageNum,
    required this.isNew,
    required this.isCurrent,
    required this.onDelete,
  });

  @override
  State<_PageManagerGridTile> createState() => _PageManagerGridTileState();
}

class _PageManagerGridTileState extends State<_PageManagerGridTile> {
  Future<Uint8List?>? _thumbFuture;

  @override
  void initState() {
    super.initState();
    _initThumb();
  }

  @override
  void didUpdateWidget(covariant _PageManagerGridTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file?.path != widget.file?.path ||
        oldWidget.pageNum != widget.pageNum ||
        oldWidget.isNew != widget.isNew) {
      _initThumb();
    }
  }

  void _initThumb() {
    if (!widget.isNew && widget.file != null && widget.pageNum > 0) {
      _thumbFuture = PdfThumbnailService.instance.getPageThumbnail(
        widget.file!.path,
        widget.pageNum,
        lastModifiedMillis: widget.file!.lastModified.millisecondsSinceEpoch,
        targetWidth: 200.0,
      );
    } else {
      _thumbFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: widget.isNew
            ? Colors.amber.shade50
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.isCurrent
              ? theme.colorScheme.primary
              : (widget.isNew ? Colors.amber.shade400 : theme.colorScheme.outlineVariant),
          width: widget.isCurrent ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (!widget.isNew && _thumbFuture != null)
            Positioned.fill(
              child: FutureBuilder<Uint8List?>(
                future: _thumbFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasData && snapshot.data != null) {
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.contain,
                    );
                  }
                  return _buildPlaceholder(theme);
                },
              ),
            )
          else
            Center(child: _buildPlaceholder(theme)),

          // Bottom page label
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              color: widget.isCurrent
                  ? theme.colorScheme.primary.withValues(alpha: 0.88)
                  : Colors.black.withValues(alpha: 0.58),
              child: Text(
                widget.isNew ? 'Blank' : 'Page ${widget.pageNum}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),

          // Top-right delete badge
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onDelete,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 16,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          widget.isNew ? Icons.note_add_rounded : Icons.description_rounded,
          size: 30,
          color: widget.isNew ? Colors.amber.shade800 : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 4),
        Text(
          widget.isNew ? 'Blank' : 'Page ${widget.pageNum}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: widget.isNew ? Colors.amber.shade900 : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

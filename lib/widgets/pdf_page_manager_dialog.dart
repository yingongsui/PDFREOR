import 'package:flutter/material.dart';
import '../models/pdf_file_info.dart';
import 'shared_pdf_thumbnail.dart';

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
  final List<int> initialDeletedZeroIndexedPages;
  final int initialAddedPagesCount;

  const PdfPageManagerDialog({
    super.key,
    this.file,
    required this.totalPages,
    required this.currentPage,
    this.initialDeletedZeroIndexedPages = const [],
    this.initialAddedPagesCount = 0,
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
    final deletedSet = widget.initialDeletedZeroIndexedPages.toSet();
    _currentPages = [
      for (int i = 0; i < widget.totalPages; i++)
        if (!deletedSet.contains(i)) i + 1,
      for (int i = 1; i <= widget.initialAddedPagesCount; i++) -i,
    ];
    if (_currentPages.isEmpty && widget.totalPages > 0) {
      _currentPages = [1];
    }
    _addedCount = widget.initialAddedPagesCount;
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

class _PageManagerGridTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: isNew
            ? Colors.amber.shade50
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrent
              ? theme.colorScheme.primary
              : (isNew ? Colors.amber.shade400 : theme.colorScheme.outlineVariant),
          width: isCurrent ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (!isNew && file != null && pageNum > 0)
            Positioned.fill(
              child: SharedPdfThumbnail.page(
                filePath: file!.path,
                lastModifiedMillis: file!.lastModified.millisecondsSinceEpoch,
                pageNumber: pageNum,
                targetWidth: 200.0,
                cacheWidth: 260,
                spinnerSize: 16,
                fallbackBuilder: (_) => Center(child: _buildPlaceholder(theme)),
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
              color: isCurrent
                  ? theme.colorScheme.primary.withValues(alpha: 0.88)
                  : Colors.black.withValues(alpha: 0.58),
              child: Text(
                isNew ? 'Blank' : 'Page $pageNum',
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
                onTap: onDelete,
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
          isNew ? Icons.note_add_rounded : Icons.description_rounded,
          size: 30,
          color: isNew ? Colors.amber.shade800 : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 4),
        Text(
          isNew ? 'Blank' : 'Page $pageNum',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: isNew ? Colors.amber.shade900 : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

class PageManagerResult {
  final List<int> deletedZeroIndexedPages;
  final int addedPagesCount;

  PageManagerResult({
    required this.deletedZeroIndexedPages,
    required this.addedPagesCount,
  });
}

class PdfPageManagerDialog extends StatefulWidget {
  final int totalPages;
  final int currentPage;

  const PdfPageManagerDialog({
    super.key,
    required this.totalPages,
    required this.currentPage,
  });

  @override
  State<PdfPageManagerDialog> createState() => _PdfPageManagerDialogState();
}

class _PdfPageManagerDialogState extends State<PdfPageManagerDialog> {
  late List<int> _currentPages; // list of 1-based original page numbers
  int _addedCount = 0;

  @override
  void initState() {
    super.initState();
    _currentPages = List.generate(widget.totalPages, (i) => i + 1);
  }

  void _addBlankPage() {
    setState(() {
      _addedCount++;
      _currentPages.add(-_addedCount); // negative number represents newly added blank page
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
        height: 380,
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
                  childAspectRatio: 0.75,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _currentPages.length,
                itemBuilder: (context, index) {
                  final pageNum = _currentPages[index];
                  final isNew = pageNum < 0;
                  final isCurrent = pageNum == widget.currentPage;

                  return Container(
                    decoration: BoxDecoration(
                      color: isNew
                          ? Colors.amber.shade50
                          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCurrent
                            ? theme.colorScheme.primary
                            : (isNew
                                ? Colors.amber.shade400
                                : theme.colorScheme.outlineVariant),
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isNew ? Icons.note_add_rounded : Icons.description_rounded,
                                size: 32,
                                color: isNew
                                    ? Colors.amber.shade800
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isNew ? 'Blank' : 'Page $pageNum',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            color: Colors.red.shade400,
                            tooltip: 'Delete page',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _deletePage(index),
                          ),
                        ),
                      ],
                    ),
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
            // Find which original pages were deleted
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

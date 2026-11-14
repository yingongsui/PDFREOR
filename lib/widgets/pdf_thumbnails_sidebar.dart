import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/pdf_file_info.dart';
import 'shared_pdf_thumbnail.dart';

class PdfThumbnailsSidebar extends StatefulWidget {
  final PdfFileInfo file;
  final int totalPages;
  final int currentPage;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onClose;

  const PdfThumbnailsSidebar({
    super.key,
    required this.file,
    required this.totalPages,
    required this.currentPage,
    required this.onPageSelected,
    required this.onClose,
  });

  @override
  State<PdfThumbnailsSidebar> createState() => _PdfThumbnailsSidebarState();
}

class _PdfThumbnailsSidebarState extends State<PdfThumbnailsSidebar> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && widget.currentPage > 1) {
        final screenSize = MediaQuery.of(context).size;
        final isTablet = screenSize.shortestSide >= 600;
        final cols = isTablet ? 2 : 1;
        final targetRow = (widget.currentPage - 1) ~/ cols;
        final targetOffset = targetRow * 190.0;
        final maxScroll = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(targetOffset.clamp(0.0, maxScroll));
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.shortestSide >= 600;
    final sidebarWidth = isTablet
        ? math.min(340.0, screenSize.width * 0.45)
        : math.min(136.0, screenSize.width * 0.38);
    final crossAxisCount = isTablet ? 2 : 1;

    return Container(
      width: sidebarWidth,
      height: screenSize.height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(-4, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 14 : 8,
                vertical: 10,
              ),
              child: Row(
                children: [
                  if (isTablet) ...[
                    Icon(
                      Icons.auto_stories_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Thumbnails',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isTablet ? '${widget.totalPages}' : '${widget.totalPages}P',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Thumbnails Grid
            Expanded(
              child: GridView.builder(
                controller: _scrollController,
                padding: EdgeInsets.all(isTablet ? 12 : 8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: isTablet ? 10 : 8,
                  mainAxisSpacing: isTablet ? 12 : 10,
                  childAspectRatio: 0.72,
                ),
                itemCount: widget.totalPages,
                itemBuilder: (context, index) {
                  final pageNumber = index + 1;
                  final isCurrent = pageNumber == widget.currentPage;

                  return _ThumbnailCard(
                    key: ValueKey('thumb_${widget.file.path}_$pageNumber'),
                    filePath: widget.file.path,
                    lastModifiedMillis: widget.file.lastModified.millisecondsSinceEpoch,
                    pageNumber: pageNumber,
                    isCurrent: isCurrent,
                    onTap: () => widget.onPageSelected(pageNumber),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailCard extends StatelessWidget {
  final String filePath;
  final int lastModifiedMillis;
  final int pageNumber;
  final bool isCurrent;
  final VoidCallback onTap;

  const _ThumbnailCard({
    super.key,
    required this.filePath,
    required this.lastModifiedMillis,
    required this.pageNumber,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCurrent
                ? const Color(0xFF1E90FF)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: isCurrent ? 2.2 : 1.0,
          ),
          boxShadow: isCurrent
              ? [
                  BoxShadow(
                    color: const Color(0xFF1E90FF).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: SharedPdfThumbnail.page(
                filePath: filePath,
                lastModifiedMillis: lastModifiedMillis,
                pageNumber: pageNumber,
                cacheWidth: 260,
                spinnerSize: 18,
                fallbackBuilder: (_) => Center(
                  child: Icon(
                    Icons.description_outlined,
                    size: 32,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? const Color(0xFF1E90FF).withValues(alpha: 0.9)
                      : Colors.black.withValues(alpha: 0.6),
                ),
                child: Text(
                  '$pageNumber',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

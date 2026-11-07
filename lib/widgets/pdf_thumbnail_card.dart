import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/pdf_file_info.dart';
import '../services/pdf_thumbnail_service.dart';

class PdfThumbnailCard extends StatefulWidget {
  final PdfFileInfo file;
  final bool isOpen;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const PdfThumbnailCard({
    super.key,
    required this.file,
    this.isOpen = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<PdfThumbnailCard> createState() => _PdfThumbnailCardState();
}

class _PdfThumbnailCardState extends State<PdfThumbnailCard> {
  Uint8List? _thumbnailBytes;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant PdfThumbnailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path ||
        oldWidget.file.lastModified != widget.file.lastModified) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final bytes = await PdfThumbnailService.instance.getThumbnail(
        widget.file.path,
        lastModifiedMillis: widget.file.lastModified.millisecondsSinceEpoch,
      );
      if (mounted) {
        setState(() {
          _thumbnailBytes = bytes;
          _isLoading = false;
          _hasError = bytes == null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('yyyy-MM-dd');
    const dodgerBlue = Color(0xFF1E90FF);

    return Card(
      elevation: widget.isOpen ? 4 : 2,
      shadowColor: widget.isOpen
          ? dodgerBlue.withValues(alpha: 0.3)
          : theme.colorScheme.shadow.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: widget.isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 2.5)
            : widget.isOpen
                ? const BorderSide(color: dodgerBlue, width: 2.5)
                : BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail Area (A4 aspect preview)
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    child: _buildThumbnailImage(theme),
                  ),

                  // Format Badge (PDF)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Text(
                        'PDF',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  // Open Badge (DodgerBlue)
                  if (widget.isOpen)
                    Positioned(
                      top: 8,
                      left: 44,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: dodgerBlue,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: dodgerBlue.withValues(alpha: 0.4),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tab_rounded, size: 10, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'OPENED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Selection indicator (only shown in selection mode)
                  if (widget.isSelectionMode)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: widget.isSelected ? theme.colorScheme.primary : Colors.black45,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 1.5,
                          ),
                        ),
                        child: widget.isSelected
                            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
            ),

            // Metadata Area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        widget.file.formattedSize,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          dateFormat.format(widget.file.lastModified),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailImage(ThemeData theme) {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    if (_hasError || _thumbnailBytes == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.picture_as_pdf_rounded,
              size: 48,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 4),
            Text(
              'PDF Preview',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Image.memory(
      _thumbnailBytes!,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (context, error, stackTrace) {
        return Center(
          child: Icon(
            Icons.picture_as_pdf_rounded,
            size: 48,
            color: Colors.red.shade400,
          ),
        );
      },
    );
  }
}


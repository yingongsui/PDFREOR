import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/pdf_file_info.dart';
import '../services/pdf_thumbnail_service.dart';

class PdfThumbnailCard extends StatefulWidget {
  final PdfFileInfo file;
  final bool isOpen;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRename;
  final VoidCallback onOpenExternal;
  final VoidCallback onShare;
  final VoidCallback onShowDetails;
  final VoidCallback? onDelete;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onPaste;
  final bool canPaste;

  const PdfThumbnailCard({
    super.key,
    required this.file,
    this.isOpen = false,
    required this.onTap,
    this.onLongPress,
    this.onRename,
    required this.onOpenExternal,
    required this.onShare,
    required this.onShowDetails,
    this.onDelete,
    this.onCopy,
    this.onCut,
    this.onPaste,
    this.canPaste = false,
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
        side: widget.isOpen
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

                  // Overflow menu button (Half size with light blue outline)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: PopupMenuButton<String>(
                      tooltip: 'More options',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 140),
                      onSelected: (value) {
                        switch (value) {
                          case 'open':
                            widget.onTap();
                            break;
                          case 'copy':
                            widget.onCopy?.call();
                            break;
                          case 'cut':
                            widget.onCut?.call();
                            break;
                          case 'paste':
                            widget.onPaste?.call();
                            break;
                          case 'rename':
                            widget.onRename?.call();
                            break;
                          case 'external':
                            widget.onOpenExternal();
                            break;
                          case 'share':
                            widget.onShare();
                            break;
                          case 'details':
                            widget.onShowDetails();
                            break;
                          case 'delete':
                            widget.onDelete?.call();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'open',
                          child: Row(
                            children: [
                              Icon(Icons.visibility_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Open Reader'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'copy',
                          child: Row(
                            children: [
                              Icon(Icons.copy_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('Copy'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'cut',
                          child: Row(
                            children: [
                              Icon(Icons.content_cut_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('Cut'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'paste',
                          enabled: widget.canPaste,
                          child: Row(
                            children: [
                              Icon(
                                Icons.paste_rounded,
                                size: 18,
                                color: widget.canPaste ? null : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Paste',
                                style: TextStyle(
                                  color: widget.canPaste ? null : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(height: 10),
                        const PopupMenuItem(
                          value: 'rename',
                          child: Row(
                            children: [
                              Icon(Icons.drive_file_rename_outline_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('Rename'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'external',
                          child: Row(
                            children: [
                              Icon(Icons.open_in_new_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('Open with External App'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'share',
                          child: Row(
                            children: [
                              Icon(Icons.share_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Share'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'details',
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 18),
                              SizedBox(width: 8),
                              Text('File Info'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(height: 10),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF90CAF9), // Light blue outline
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.more_vert, size: 13, color: Colors.black87),
                        ),
                      ),
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
                      const Spacer(),
                      Text(
                        dateFormat.format(widget.file.lastModified),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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


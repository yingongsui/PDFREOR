import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/pdf_file_info.dart';
import '../services/pdf_thumbnail_service.dart';

class PdfListTile extends StatefulWidget {
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

  const PdfListTile({
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
  State<PdfListTile> createState() => _PdfListTileState();
}

class _PdfListTileState extends State<PdfListTile> {
  Uint8List? _thumbnailBytes;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant PdfListTile oldWidget) {
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
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    const dodgerBlue = Color(0xFF1E90FF);

    return Card(
      elevation: widget.isOpen ? 2 : 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: widget.isOpen
            ? const BorderSide(color: dodgerBlue, width: 2.2)
            : BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // Leading Thumbnail
              Container(
                width: 52,
                height: 68,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.isOpen
                        ? dodgerBlue.withValues(alpha: 0.6)
                        : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildThumbnail(theme),
              ),
              const SizedBox(width: 14),

              // Title and Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.file.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (widget.isOpen) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: dodgerBlue,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.tab_rounded, size: 9, color: Colors.white),
                                SizedBox(width: 2),
                                Text(
                                  'OPENED',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.file.formattedSize,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (widget.file.parentDirectoryName.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '📁 ${widget.file.parentDirectoryName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(widget.file.lastModified),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),

              // Trailing action menu
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
                        Text('File Details'),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(ThemeData theme) {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    if (_hasError || _thumbnailBytes == null) {
      return Center(
        child: Icon(
          Icons.picture_as_pdf_rounded,
          size: 28,
          color: Colors.red.shade400,
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
            size: 28,
            color: Colors.red.shade400,
          ),
        );
      },
    );
  }
}

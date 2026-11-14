import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/pdf_file_info.dart';
import 'shared_pdf_thumbnail.dart';

class PdfListTile extends StatelessWidget {
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  final PdfFileInfo file;
  final bool isOpen;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const PdfListTile({
    super.key,
    required this.file,
    this.isOpen = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = _dateFormat;
    const dodgerBlue = Color(0xFF1E90FF);

    return Card(
      elevation: isOpen ? 2 : 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 2.2)
            : isOpen
                ? const BorderSide(color: dodgerBlue, width: 2.2)
                : BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
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
                    color: isOpen
                        ? dodgerBlue.withValues(alpha: 0.6)
                        : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: SharedPdfThumbnail.cover(
                  filePath: file.path,
                  lastModifiedMillis: file.lastModified.millisecondsSinceEpoch,
                  cacheWidth: 160,
                  spinnerSize: 16,
                  spinnerColor: theme.colorScheme.primary.withValues(alpha: 0.6),
                  fallbackBuilder: (_) => Center(
                    child: Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 28,
                      color: Colors.red.shade400,
                    ),
                  ),
                ),
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
                            file.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (isOpen) ...[
                          const SizedBox(width: 6),
                          const PdfOpenedBadge(compact: true),
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
                            file.formattedSize,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (file.parentDirectoryName.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '📁 ${file.parentDirectoryName}',
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
                      dateFormat.format(file.lastModified),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),

              // Selection indicator when in selection mode
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: PdfSelectionBadge(isSelected: isSelected),
                ),
            ],
          ),
        ),
      ),
    );
  }

}

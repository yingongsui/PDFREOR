import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

/// Compact floating search bar for finding text inside the active PDF document.
class PdfSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final pdfrx.PdfTextSearcher? searcher;
  final bool matchCase;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleMatchCase;
  final VoidCallback onClose;

  const PdfSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.searcher,
    required this.matchCase,
    required this.onChanged,
    required this.onSubmitted,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleMatchCase,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusListenable = searcher == null
        ? controller
        : Listenable.merge([controller, searcher!]);

    return Align(
      alignment: Alignment.topRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(14),
          color: theme.colorScheme.surface,
          shadowColor: Colors.black26,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: Row(
              children: [
                if (searcher != null)
                  ListenableBuilder(
                    listenable: searcher!,
                    builder: (context, _) {
                      if (searcher!.isSearching) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Find in PDF...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                    ),
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                  ),
                ),
                ListenableBuilder(
                  listenable: statusListenable,
                  builder: (context, _) {
                    final activeSearcher = searcher;
                    final matches = activeSearcher?.matches ?? const [];
                    final currentIdx = activeSearcher?.currentIndex;
                    final isSearching = activeSearcher?.isSearching ?? false;
                    final hasQuery = controller.text.trim().isNotEmpty;
                    final hasMatches = matches.isNotEmpty;

                    final String statusText;
                    if (!hasQuery) {
                      statusText = '';
                    } else if (hasMatches) {
                      final displayIndex = (currentIdx ?? 0) + 1;
                      statusText = '$displayIndex/${matches.length}';
                    } else if (isSearching) {
                      statusText = '...';
                    } else {
                      statusText = '0/0';
                    }

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (statusText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: !hasMatches && !isSearching
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (controller.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.backspace_outlined, size: 17),
                            tooltip: 'Clear query',
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            onPressed: () {
                              controller.clear();
                              onChanged('');
                              focusNode.requestFocus();
                            },
                          ),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: onToggleMatchCase,
                          child: Tooltip(
                            message: 'Match case',
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                color: matchCase
                                    ? theme.colorScheme.primaryContainer
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: matchCase
                                      ? theme.colorScheme.primary.withValues(alpha: 0.6)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                'Aa',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: matchCase
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                          tooltip: 'Previous match',
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: hasMatches ? onPrevious : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                          tooltip: 'Next match',
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: hasMatches ? onNext : null,
                        ),
                      ],
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 19),
                  tooltip: 'Close find',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

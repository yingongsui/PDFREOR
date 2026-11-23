import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// Compact floating bar inside the PDF viewer for searching text strings
/// within the currently open document.
class PdfFindBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool matchCase;
  final bool isSearching;
  final int matchCount;
  final int? currentMatchIndex;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleMatchCase;
  final VoidCallback onFindNext;
  final VoidCallback onFindPrevious;
  final VoidCallback onClose;

  const PdfFindBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.matchCase,
    required this.isSearching,
    required this.matchCount,
    required this.currentMatchIndex,
    required this.query,
    required this.onQueryChanged,
    required this.onToggleMatchCase,
    required this.onFindNext,
    required this.onFindPrevious,
    required this.onClose,
  });

  @override
  State<PdfFindBar> createState() => _PdfFindBarState();
}

class _PdfFindBarState extends State<PdfFindBar> {
  String get _statusText {
    if (widget.query.isEmpty) {
      return '';
    }
    if (widget.isSearching && widget.matchCount == 0) {
      return '...';
    }
    if (widget.matchCount == 0) {
      return '0 / 0';
    }
    final displayIdx = (widget.currentMatchIndex ?? 0) + 1;
    return widget.isSearching
        ? '$displayIdx / ${widget.matchCount}+'
        : '$displayIdx / ${widget.matchCount}';
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        HardwareKeyboard.instance.isShiftPressed) {
      widget.onFindPrevious();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasQuery = widget.query.isNotEmpty;
    final hasMatches = widget.matchCount > 0;

    return Material(
      elevation: 6,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(12),
      color: isDark ? const Color(0xFF25282C) : Colors.white,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
        child: Focus(
          onKeyEvent: _handleKeyEvent,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.search,
                size: 18,
                color: Color(0xFF1E90FF),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Find in PDF...',
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  onChanged: widget.onQueryChanged,
                  onSubmitted: (_) => widget.onFindNext(),
                ),
              ),
              if (hasQuery) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    _statusText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: (!widget.isSearching && !hasMatches)
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              Tooltip(
                message: 'Match Case',
                child: InkWell(
                  onTap: widget.onToggleMatchCase,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.matchCase
                          ? const Color(0xFF1E90FF).withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: widget.matchCase
                            ? const Color(0xFF1E90FF)
                            : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      'Aa',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: widget.matchCase
                            ? const Color(0xFF1E90FF)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up, size: 19),
                tooltip: 'Previous match (Shift+Enter)',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                onPressed: hasMatches ? widget.onFindPrevious : null,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 19),
                tooltip: 'Next match (Enter)',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                onPressed: hasMatches ? widget.onFindNext : null,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 17),
                tooltip: 'Close (Esc)',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

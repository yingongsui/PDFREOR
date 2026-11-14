import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../services/editor_settings_service.dart';

class LatexOperatorsCard extends StatelessWidget {
  final EditorSettings editorSettings;
  final Future<void> Function(EditorSettings updated) onSettingsUpdated;

  const LatexOperatorsCard({
    super.key,
    required this.editorSettings,
    required this.onSettingsUpdated,
  });

  Future<void> _showAddOperatorDialog(BuildContext context) async {
    final added = await showDialog<String>(
      context: context,
      builder: (_) => const AddOperatorDialog(),
    );
    if (added == null || added.isEmpty) return;
    final current = List<String>.from(editorSettings.latexQuickOperators);
    if (!current.contains(added)) {
      current.add(added);
      await onSettingsUpdated(
        editorSettings.copyWith(latexQuickOperators: current),
      );
    }
  }

  Future<void> _showReorderOperatorsSheet(BuildContext context) async {
    final theme = Theme.of(context);
    final reorderedList = List<String>.from(editorSettings.latexQuickOperators);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(Icons.swap_vert_rounded, color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          const Text(
                            'Reorder Operators',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          FilledButton.tonal(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Drag the handle on the right to reorder formula shortcuts',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: ReorderableListView.builder(
                        itemCount: reorderedList.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setSheetState(() {
                            final item = reorderedList.removeAt(oldIndex);
                            reorderedList.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final op = reorderedList[index];
                          return ListTile(
                            key: ValueKey('op_reorder_$op'),
                            leading: Container(
                              width: 52,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                              child: Math.tex(
                                op,
                                textStyle: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface,
                                ),
                                mathStyle: MathStyle.display,
                                onErrorFallback: (_) => Text(op, style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                            title: Text(
                              op,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Icon(Icons.drag_handle_rounded, color: Colors.grey),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    await onSettingsUpdated(
      editorSettings.copyWith(latexQuickOperators: reorderedList),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final operators = editorSettings.latexQuickOperators;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.functions_rounded, color: theme.colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Math Formula Operators',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Quick shortcuts available when editing formulas • Drag to reorder',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < operators.length; i++)
                  DragTarget<int>(
                    onWillAcceptWithDetails: (details) => details.data != i,
                    onAcceptWithDetails: (details) async {
                      final oldIndex = details.data;
                      final newIndex = i;
                      final updatedList = List<String>.from(operators);
                      final item = updatedList.removeAt(oldIndex);
                      updatedList.insert(newIndex, item);
                      await onSettingsUpdated(
                        editorSettings.copyWith(latexQuickOperators: updatedList),
                      );
                    },
                    builder: (context, candidateData, rejectedData) {
                      final isTargeted = candidateData.isNotEmpty;
                      final chipWidget = InputChip(
                        avatar: Icon(
                          Icons.drag_indicator_rounded,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        label: Math.tex(
                          operators[i],
                          textStyle: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface,
                          ),
                          mathStyle: MathStyle.display,
                          onErrorFallback: (_) => Text(
                            operators[i],
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        deleteIcon: const Icon(Icons.close_rounded, size: 14),
                        onDeleted: () async {
                          final updatedList = List<String>.from(operators)..removeAt(i);
                          await onSettingsUpdated(
                            editorSettings.copyWith(latexQuickOperators: updatedList),
                          );
                        },
                      );

                      return LongPressDraggable<int>(
                        data: i,
                        delay: const Duration(milliseconds: 180),
                        hapticFeedbackOnStart: true,
                        feedback: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: theme.colorScheme.primary, width: 1.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
                              ],
                            ),
                            child: Math.tex(
                              operators[i],
                              textStyle: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                              mathStyle: MathStyle.display,
                              onErrorFallback: (_) => Text(operators[i]),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(opacity: 0.25, child: chipWidget),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: isTargeted
                                ? Border.all(color: theme.colorScheme.primary, width: 2)
                                : null,
                            color: isTargeted
                                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                                : Colors.transparent,
                          ),
                          child: chipWidget,
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showAddOperatorDialog(context),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Operator'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showReorderOperatorsSheet(context),
                  icon: const Icon(Icons.swap_vert_rounded, size: 16),
                  label: const Text('Reorder List'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await onSettingsUpdated(
                      editorSettings.copyWith(latexQuickOperators: kDefaultLatexOperators),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Operators reset to default'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.restore_rounded, size: 16),
                  label: const Text('Reset Defaults'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AddOperatorDialog extends StatefulWidget {
  const AddOperatorDialog({super.key});

  @override
  State<AddOperatorDialog> createState() => _AddOperatorDialogState();
}

class _AddOperatorDialogState extends State<AddOperatorDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.functions_rounded, color: Colors.blue),
          SizedBox(width: 8),
          Text('Add Math Operator'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Enter a LaTeX operator or formula snippet to add to the quick bar:',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: r'e.g. \vec{v}, \mathbb{R}, \nabla',
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final text = value.text.trim();
              return Container(
                constraints: const BoxConstraints(minHeight: 38),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                alignment: Alignment.center,
                child: Math.tex(
                  text.isEmpty ? r'\dots' : text,
                  textStyle: const TextStyle(fontSize: 16),
                  mathStyle: MathStyle.display,
                  onErrorFallback: (err) => Text(
                    'Invalid: ${err.message}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) {
            final text = value.text.trim();
            return FilledButton(
              onPressed: text.isEmpty ? null : () => Navigator.pop(context, text),
              child: const Text('Add'),
            );
          },
        ),
      ],
    );
  }
}

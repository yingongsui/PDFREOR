import 'package:material_ui/material_ui.dart';
import 'home_dialogs.dart';
import 'home_models.dart';

class _SortOption<T> {
  final T value;
  final String label;
  final IconData icon;

  const _SortOption(this.value, this.label, this.icon);
}

const List<_SortOption<FolderSortType>> _folderSortOptions = [
  _SortOption(FolderSortType.nameAsc, 'Name: A to Z', Icons.sort_by_alpha_rounded),
  _SortOption(FolderSortType.nameDesc, 'Name: Z to A', Icons.sort_by_alpha_rounded),
  _SortOption(FolderSortType.pathAsc, 'Path: A to Z', Icons.folder_open_rounded),
  _SortOption(FolderSortType.pathDesc, 'Path: Z to A', Icons.folder_open_rounded),
  _SortOption(FolderSortType.fileCountDesc, 'Files: Most First', Icons.format_list_numbered_rounded),
  _SortOption(FolderSortType.fileCountAsc, 'Files: Fewest First', Icons.format_list_numbered_rounded),
  _SortOption(FolderSortType.dateDesc, 'Date: Newest First', Icons.calendar_today_rounded),
  _SortOption(FolderSortType.dateAsc, 'Date: Oldest First', Icons.history_rounded),
];

const List<_SortOption<SortType>> _fileSortOptions = [
  _SortOption(SortType.dateDesc, 'Date: Newest First', Icons.calendar_today_rounded),
  _SortOption(SortType.dateAsc, 'Date: Oldest First', Icons.history_rounded),
  _SortOption(SortType.nameAsc, 'Name: A to Z', Icons.sort_by_alpha_rounded),
  _SortOption(SortType.nameDesc, 'Name: Z to A', Icons.sort_by_alpha_rounded),
  _SortOption(SortType.sizeDesc, 'Size: Largest First', Icons.storage_rounded),
  _SortOption(SortType.sizeAsc, 'Size: Smallest First', Icons.data_usage_rounded),
];

void showHomeSortOptionsSheet(
  BuildContext context, {
  required FolderSortType initialFolderSort,
  required SortType initialFileSort,
  required ValueChanged<FolderSortType> onFolderSortChanged,
  required ValueChanged<SortType> onFileSortChanged,
}) {
  final theme = Theme.of(context);
  var currentFolderSort = initialFolderSort;
  var currentFileSort = initialFileSort;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SheetDragHandle(),
                  Row(
                    children: [
                      Icon(Icons.tune_rounded, color: theme.colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Sort Options',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildSortSectionHeader(
                    icon: Icons.folder_rounded,
                    title: 'FOLDER SORTING',
                    theme: theme,
                  ),
                  const SizedBox(height: 8),
                  _buildSortChipGroup<FolderSortType>(
                    options: _folderSortOptions,
                    current: currentFolderSort,
                    theme: theme,
                    onSelected: (val) {
                      currentFolderSort = val;
                      onFolderSortChanged(val);
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 20),
                  _buildSortSectionHeader(
                    icon: Icons.description_rounded,
                    title: 'FILE SORTING',
                    theme: theme,
                  ),
                  const SizedBox(height: 8),
                  _buildSortChipGroup<SortType>(
                    options: _fileSortOptions,
                    current: currentFileSort,
                    theme: theme,
                    onSelected: (val) {
                      currentFileSort = val;
                      onFileSortChanged(val);
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _buildSortSectionHeader({
  required IconData icon,
  required String title,
  required ThemeData theme,
}) {
  return Row(
    children: [
      Icon(icon, size: 16, color: theme.colorScheme.primary),
      const SizedBox(width: 6),
      Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: theme.colorScheme.primary,
        ),
      ),
    ],
  );
}

Widget _buildSortChipGroup<T>({
  required List<_SortOption<T>> options,
  required T current,
  required ValueChanged<T> onSelected,
  required ThemeData theme,
}) {
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final option in options)
        _buildSortChip<T>(
          current: current,
          target: option.value,
          label: option.label,
          icon: option.icon,
          onSelected: onSelected,
          theme: theme,
        ),
    ],
  );
}

Widget _buildSortChip<T>({
  required T current,
  required T target,
  required String label,
  required IconData icon,
  required ValueChanged<T> onSelected,
  required ThemeData theme,
}) {
  final isSelected = current == target;
  return ChoiceChip(
    selected: isSelected,
    avatar: Icon(
      icon,
      size: 16,
      color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
    ),
    label: Text(label),
    labelStyle: TextStyle(
      fontSize: 12,
      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
    ),
    selectedColor: theme.colorScheme.primary,
    onSelected: (_) => onSelected(target),
  );
}

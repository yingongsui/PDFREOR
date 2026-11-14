import 'package:flutter/material.dart';
import 'home_dialogs.dart';
import 'home_models.dart';

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

                  // Folder Sorting Header
                  Row(
                    children: [
                      Icon(Icons.folder_rounded, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'FOLDER SORTING',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildSortChip<FolderSortType>(
                        current: currentFolderSort,
                        target: FolderSortType.nameAsc,
                        label: 'Name: A to Z',
                        icon: Icons.sort_by_alpha_rounded,
                        onSelected: (val) {
                          currentFolderSort = val;
                          onFolderSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                      _buildSortChip<FolderSortType>(
                        current: currentFolderSort,
                        target: FolderSortType.nameDesc,
                        label: 'Name: Z to A',
                        icon: Icons.sort_by_alpha_rounded,
                        onSelected: (val) {
                          currentFolderSort = val;
                          onFolderSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                      _buildSortChip<FolderSortType>(
                        current: currentFolderSort,
                        target: FolderSortType.pathAsc,
                        label: 'Path: A to Z',
                        icon: Icons.folder_open_rounded,
                        onSelected: (val) {
                          currentFolderSort = val;
                          onFolderSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                      _buildSortChip<FolderSortType>(
                        current: currentFolderSort,
                        target: FolderSortType.pathDesc,
                        label: 'Path: Z to A',
                        icon: Icons.folder_open_rounded,
                        onSelected: (val) {
                          currentFolderSort = val;
                          onFolderSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                      _buildSortChip<FolderSortType>(
                        current: currentFolderSort,
                        target: FolderSortType.fileCountDesc,
                        label: 'Files: Most First',
                        icon: Icons.format_list_numbered_rounded,
                        onSelected: (val) {
                          currentFolderSort = val;
                          onFolderSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                      _buildSortChip<FolderSortType>(
                        current: currentFolderSort,
                        target: FolderSortType.fileCountAsc,
                        label: 'Files: Fewest First',
                        icon: Icons.format_list_numbered_rounded,
                        onSelected: (val) {
                          currentFolderSort = val;
                          onFolderSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                      _buildSortChip<FolderSortType>(
                        current: currentFolderSort,
                        target: FolderSortType.dateDesc,
                        label: 'Date: Newest First',
                        icon: Icons.calendar_today_rounded,
                        onSelected: (val) {
                          currentFolderSort = val;
                          onFolderSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                      _buildSortChip<FolderSortType>(
                        current: currentFolderSort,
                        target: FolderSortType.dateAsc,
                        label: 'Date: Oldest First',
                        icon: Icons.history_rounded,
                        onSelected: (val) {
                          currentFolderSort = val;
                          onFolderSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // File Sorting Header
                  Row(
                    children: [
                      Icon(Icons.description_rounded, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'FILE SORTING',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildSortChip<SortType>(
                        current: currentFileSort,
                        target: SortType.dateDesc,
                        label: 'Date: Newest First',
                        icon: Icons.calendar_today_rounded,
                        onSelected: (val) {
                          currentFileSort = val;
                          onFileSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                      _buildSortChip<SortType>(
                        current: currentFileSort,
                        target: SortType.dateAsc,
                        label: 'Date: Oldest First',
                        icon: Icons.history_rounded,
                        onSelected: (val) {
                          currentFileSort = val;
                          onFileSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                      _buildSortChip<SortType>(
                        current: currentFileSort,
                        target: SortType.nameAsc,
                        label: 'Name: A to Z',
                        icon: Icons.sort_by_alpha_rounded,
                        onSelected: (val) {
                          currentFileSort = val;
                          onFileSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                      _buildSortChip<SortType>(
                        current: currentFileSort,
                        target: SortType.nameDesc,
                        label: 'Name: Z to A',
                        icon: Icons.sort_by_alpha_rounded,
                        onSelected: (val) {
                          currentFileSort = val;
                          onFileSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                      _buildSortChip<SortType>(
                        current: currentFileSort,
                        target: SortType.sizeDesc,
                        label: 'Size: Largest First',
                        icon: Icons.storage_rounded,
                        onSelected: (val) {
                          currentFileSort = val;
                          onFileSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                      _buildSortChip<SortType>(
                        current: currentFileSort,
                        target: SortType.sizeAsc,
                        label: 'Size: Smallest First',
                        icon: Icons.data_usage_rounded,
                        onSelected: (val) {
                          currentFileSort = val;
                          onFileSortChanged(val);
                          setSheetState(() {});
                        },
                        theme: theme,
                      ),
                    ],
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

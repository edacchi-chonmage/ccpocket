import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/diff_parser.dart';
import 'diff_binary_notice.dart';
import 'diff_file_header.dart';
import 'diff_hunk_widget.dart';
import 'diff_image_widget.dart';

class DiffContentList extends StatelessWidget {
  final List<DiffFile> files;
  final Set<int> hiddenFileIndices;
  final Set<int> collapsedFileIndices;
  final ValueChanged<int> onToggleCollapse;
  final VoidCallback onClearHidden;
  final bool selectionMode;
  final Set<String> selectedHunkKeys;
  final ValueChanged<int>? onToggleFileSelection;
  final void Function(int fileIdx, int hunkIdx)? onToggleHunkSelection;
  final bool Function(int fileIdx)? isFileFullySelected;
  final bool Function(int fileIdx)? isFilePartiallySelected;
  final ValueChanged<int>? onLoadImage;
  final Set<int> loadingImageIndices;
  final ValueChanged<int>? onSwipeStage;
  final ValueChanged<int>? onSwipeUnstage;
  final ValueChanged<int>? onSwipeRevert;
  final ValueChanged<int>? onLongPressFile;
  final void Function(int fileIdx, int hunkIdx)? onSwipeStageHunk;
  final void Function(int fileIdx, int hunkIdx)? onSwipeUnstageHunk;
  final void Function(int fileIdx, int hunkIdx)? onSwipeRevertHunk;
  final void Function(int fileIdx, int hunkIdx)? onLongPressHunk;
  final bool lineWrapEnabled;
  final Set<String> stagedFilePaths;

  const DiffContentList({
    super.key,
    required this.files,
    required this.hiddenFileIndices,
    required this.collapsedFileIndices,
    required this.onToggleCollapse,
    required this.onClearHidden,
    this.selectionMode = false,
    this.selectedHunkKeys = const {},
    this.onToggleFileSelection,
    this.onToggleHunkSelection,
    this.isFileFullySelected,
    this.isFilePartiallySelected,
    this.onLoadImage,
    this.loadingImageIndices = const {},
    this.onSwipeStage,
    this.onSwipeUnstage,
    this.onSwipeRevert,
    this.onLongPressFile,
    this.onSwipeStageHunk,
    this.onSwipeUnstageHunk,
    this.onSwipeRevertHunk,
    this.onLongPressHunk,
    this.lineWrapEnabled = false,
    this.stagedFilePaths = const {},
  });

  FileStageStatus _stageStatusFor(DiffFile file) {
    if (stagedFilePaths.isEmpty) return FileStageStatus.unknown;
    return stagedFilePaths.contains(file.filePath)
        ? FileStageStatus.staged
        : FileStageStatus.unstaged;
  }

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;

    // Single-file mode: show file header + hunks (no filter/divider)
    if (files.length == 1) {
      final file = files.first;
      if (file.isBinary) {
        if (file.isImage && file.imageData != null) {
          return DiffImageWidget(
            file: file,
            imageData: file.imageData!,
            onLoadRequested: onLoadImage != null ? () => onLoadImage!(0) : null,
            loading: loadingImageIndices.contains(0),
          );
        }
        return const DiffBinaryNotice();
      }
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [_buildFileSection(0, file)],
      );
    }

    // Multi-file mode: all visible files in one scrollable list
    final visibleFiles = <int>[];
    for (var i = 0; i < files.length; i++) {
      if (!hiddenFileIndices.contains(i)) visibleFiles.add(i);
    }

    if (visibleFiles.isEmpty) {
      final l = AppLocalizations.of(context);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_off, size: 48, color: appColors.subtleText),
            const SizedBox(height: 12),
            Text(
              l.allFilesFilteredOut,
              style: TextStyle(fontSize: 16, color: appColors.subtleText),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onClearHidden, child: Text(l.showAll)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: visibleFiles.length * 2 - 1,
      itemBuilder: (context, index) {
        if (index.isOdd) {
          return Divider(height: 24, thickness: 1, color: appColors.codeBorder);
        }
        final fileIdx = visibleFiles[index ~/ 2];
        return _buildFileSection(fileIdx, files[fileIdx]);
      },
    );
  }

  Widget _buildFileSection(int fileIdx, DiffFile file) {
    final collapsed = collapsedFileIndices.contains(fileIdx);
    final header = DiffFileHeader(
      file: file,
      collapsed: collapsed,
      onToggleCollapse: () => onToggleCollapse(fileIdx),
      selectionMode: selectionMode,
      selected: isFileFullySelected?.call(fileIdx) ?? false,
      partiallySelected: isFilePartiallySelected?.call(fileIdx) ?? false,
      onToggleSelection: onToggleFileSelection != null
          ? () => onToggleFileSelection!(fileIdx)
          : null,
      stageStatus: _stageStatusFor(file),
      onLongPress: onLongPressFile != null
          ? () => onLongPressFile!(fileIdx)
          : null,
    );

    Widget section = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (!collapsed)
          if (file.isBinary)
            if (file.isImage && file.imageData != null)
              DiffImageWidget(
                file: file,
                imageData: file.imageData!,
                onLoadRequested: onLoadImage != null
                    ? () => onLoadImage!(fileIdx)
                    : null,
                loading: loadingImageIndices.contains(fileIdx),
              )
            else
              const DiffBinaryNotice()
          else
            ..._buildHunkWidgets(fileIdx, file),
      ],
    );

    if (onSwipeStage != null ||
        onSwipeUnstage != null ||
        onSwipeRevert != null) {
      section = _SwipeStageDismissible(
        fileIdx: fileIdx,
        filePath: file.filePath,
        onSwipeStage: onSwipeStage,
        onSwipeUnstage: onSwipeUnstage,
        onSwipeRevert: onSwipeRevert,
        child: section,
      );
    }
    return section;
  }

  List<Widget> _buildHunkWidgets(int fileIdx, DiffFile file) {
    final lineNumberWidth = calcLineNumberWidth(file);
    return [
      for (var hunkIdx = 0; hunkIdx < file.hunks.length; hunkIdx++)
        DiffHunkWidget(
          hunk: file.hunks[hunkIdx],
          lineNumberWidth: lineNumberWidth,
          dismissKey: '${file.filePath}:$hunkIdx',
          selectionMode: selectionMode,
          selected: selectedHunkKeys.contains('$fileIdx:$hunkIdx'),
          lineWrapEnabled: lineWrapEnabled,
          onToggleSelection: onToggleHunkSelection != null
              ? () => onToggleHunkSelection!(fileIdx, hunkIdx)
              : null,
          onLongPressHeader: !selectionMode && onLongPressHunk != null
              ? () => onLongPressHunk!(fileIdx, hunkIdx)
              : null,
          onSwipeStage: !selectionMode && onSwipeStageHunk != null
              ? () => onSwipeStageHunk!(fileIdx, hunkIdx)
              : null,
          onSwipeUnstage: !selectionMode && onSwipeUnstageHunk != null
              ? () => onSwipeUnstageHunk!(fileIdx, hunkIdx)
              : null,
          onSwipeRevert: !selectionMode && onSwipeRevertHunk != null
              ? () => onSwipeRevertHunk!(fileIdx, hunkIdx)
              : null,
        ),
    ];
  }
}

/// Wraps a file header with swipe gestures:
/// - Right swipe → Stage (green)
/// - Left swipe → Unstage (amber) or Revert/Discard (red)
class _SwipeStageDismissible extends StatelessWidget {
  final int fileIdx;
  final String filePath;
  final ValueChanged<int>? onSwipeStage;
  final ValueChanged<int>? onSwipeUnstage;
  final ValueChanged<int>? onSwipeRevert;
  final Widget child;

  const _SwipeStageDismissible({
    required this.fileIdx,
    required this.filePath,
    this.onSwipeStage,
    this.onSwipeUnstage,
    this.onSwipeRevert,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Determine left swipe action: Revert takes priority, then Unstage
    final hasLeftAction = onSwipeRevert != null || onSwipeUnstage != null;
    final isRevert = onSwipeRevert != null;
    final leftLabel = isRevert ? 'Revert' : 'Unstage';
    final leftColor = isRevert ? cs.error : cs.tertiary;
    final leftIcon = isRevert ? Icons.undo : Icons.remove_circle_outline;

    // Determine swipe direction
    final direction = onSwipeStage != null && hasLeftAction
        ? DismissDirection.horizontal
        : onSwipeStage != null
        ? DismissDirection.startToEnd
        : hasLeftAction
        ? DismissDirection.endToStart
        : DismissDirection.none;

    return Dismissible(
      key: ValueKey('swipe_stage_$filePath'),
      direction: direction,
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onSwipeStage?.call(fileIdx);
        } else {
          if (onSwipeRevert != null) {
            onSwipeRevert!.call(fileIdx);
          } else {
            onSwipeUnstage?.call(fileIdx);
          }
        }
        return false;
      },
      background: onSwipeStage != null
          ? Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20),
              color: cs.primary.withValues(alpha: 0.15),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_outline, color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Stage',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          : hasLeftAction
          ? const SizedBox.shrink()
          : null,
      secondaryBackground: hasLeftAction
          ? Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: leftColor.withValues(alpha: 0.15),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    leftLabel,
                    style: TextStyle(
                      color: leftColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(leftIcon, color: leftColor, size: 20),
                ],
              ),
            )
          : null,
      child: child,
    );
  }
}

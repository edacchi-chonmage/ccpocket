import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../l10n/app_localizations.dart';
import '../../services/bridge_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/diff_parser.dart'
    show DiffSelection, reconstructDiff, reconstructUnifiedDiff;
import 'state/commit_cubit.dart';
import 'state/git_view_cubit.dart';
import 'state/git_view_state.dart';
import 'widgets/branch_selector_sheet.dart';
import 'widgets/commit_bottom_sheet.dart';
import 'widgets/diff_content_list.dart';
import 'widgets/diff_empty_state.dart';
import 'widgets/diff_error_state.dart';

/// Dedicated screen for viewing unified diffs.
///
/// Two modes:
/// - **Individual diff**: Pass [initialDiff] with raw diff text (from tool_result).
/// - **Session-wide diff**: Pass [projectPath] to request `git diff` from Bridge.
///
/// Returns a [DiffSelection] via [Navigator.pop] when Request Change is chosen.
@RoutePage()
class GitScreen extends StatelessWidget {
  /// Raw diff text for immediate display (individual tool result).
  final String? initialDiff;

  /// Project path — triggers `git diff` request on init.
  final String? projectPath;

  /// Display title (e.g. file path for individual diff).
  final String? title;

  /// Worktree path (if the session runs in a worktree).
  final String? worktreePath;

  /// Session ID (for updating session branch info after checkout).
  final String? sessionId;

  const GitScreen({
    super.key,
    this.initialDiff,
    this.projectPath,
    this.title,
    this.worktreePath,
    this.sessionId,
  });

  @override
  Widget build(BuildContext context) {
    final bridge = context.read<BridgeService>();
    final isProjectMode = projectPath != null;

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => GitViewCubit(
            bridge: bridge,
            initialDiff: initialDiff,
            projectPath: projectPath,
            worktreePath: worktreePath,
            sessionId: sessionId,
          ),
        ),
        if (isProjectMode)
          BlocProvider(
            create: (_) =>
                CommitCubit(bridge: bridge, projectPath: projectPath!),
          ),
      ],
      child: _GitScreenBody(title: title, isProjectMode: isProjectMode),
    );
  }
}

class _GitScreenBody extends StatelessWidget {
  final String? title;
  final bool isProjectMode;

  const _GitScreenBody({this.title, this.isProjectMode = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<GitViewCubit>().state;
    final cubit = context.read<GitViewCubit>();
    final l = AppLocalizations.of(context);

    final screenTitle = title ?? l.changes;

    return Scaffold(
      appBar: AppBar(
        title: Text(screenTitle, overflow: TextOverflow.ellipsis),
        bottom: isProjectMode
            ? PreferredSize(
                preferredSize: const Size.fromHeight(72),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Branch indicator
                    _BranchIndicator(
                      branchName: state.currentBranch,
                      isWorktree: state.isWorktree,
                      projectPath: cubit.projectPath,
                    ),
                    // View mode tabs
                    _GitViewModeSegment(
                      viewMode: state.viewMode,
                      onChanged: cubit.switchMode,
                    ),
                  ],
                ),
              )
            : null,
        actions: [
          // Refresh (projectPath mode only)
          if (cubit.canRefresh && !state.loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l.refresh,
              onPressed: cubit.refresh,
            ),
        ],
      ),
      bottomNavigationBar: isProjectMode
          ? _DiffBottomBar(
              state: state,
              cubit: cubit,
              onCommit: () => showCommitBottomSheet(context),
              onPull: cubit.pull,
              onPush: cubit.push,
            )
          : null,
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
          ? DiffErrorState(error: state.error!, errorCode: state.errorCode)
          : state.files.isEmpty
          ? DiffEmptyState(viewMode: isProjectMode ? state.viewMode : null)
          : DiffContentList(
              files: state.files,
              collapsedFileIndices: state.collapsedFileIndices,
              onToggleCollapse: cubit.toggleCollapse,
              onLoadImage: cubit.loadImage,
              loadingImageIndices: state.loadingImageIndices,
              // Staged tab: only unstage swipe. Changes tab: stage + revert.
              onSwipeStage:
                  isProjectMode && state.viewMode != GitViewMode.staged
                  ? cubit.stageFile
                  : null,
              onSwipeUnstage:
                  isProjectMode && state.viewMode == GitViewMode.staged
                  ? cubit.unstageFile
                  : null,
              onSwipeRevert:
                  isProjectMode && state.viewMode != GitViewMode.staged
                  ? (fileIdx) => _confirmRevert(
                      context,
                      title: 'この変更を破棄しますか',
                      message: 'このファイルの未ステージ変更をすべて破棄します。',
                      onConfirm: () => cubit.revertFile(fileIdx),
                    )
                  : null,
              onSwipeStageHunk:
                  isProjectMode && state.viewMode == GitViewMode.unstaged
                  ? cubit.stageHunk
                  : null,
              onSwipeUnstageHunk:
                  isProjectMode && state.viewMode == GitViewMode.staged
                  ? cubit.unstageHunk
                  : null,
              onSwipeRevertHunk:
                  isProjectMode && state.viewMode == GitViewMode.unstaged
                  ? (fileIdx, hunkIdx) => _confirmRevert(
                      context,
                      title: 'この変更を破棄しますか',
                      message: 'このハンクの未ステージ変更を破棄します。',
                      onConfirm: () => cubit.revertHunk(fileIdx, hunkIdx),
                    )
                  : null,
              onLongPressFile: isProjectMode
                  ? (fileIdx) =>
                        _showFileActionSheet(context, cubit, state, fileIdx)
                  : null,
              onLongPressHunk: isProjectMode
                  ? (fileIdx, hunkIdx) => _showHunkActionSheet(
                      context,
                      cubit,
                      state,
                      fileIdx,
                      hunkIdx,
                    )
                  : null,
              lineWrapEnabled: state.lineWrapEnabled,
            ),
    );
  }

  void _showFileActionSheet(
    BuildContext context,
    GitViewCubit cubit,
    GitViewState state,
    int fileIdx,
  ) {
    if (fileIdx >= state.files.length) return;
    final file = state.files[fileIdx];
    final cs = Theme.of(context).colorScheme;
    final isStaged = state.viewMode == GitViewMode.staged;

    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                file.filePath,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            // Stage (only in Changes tab)
            if (!isStaged)
              ListTile(
                leading: Icon(Icons.add_circle_outline, color: cs.primary),
                title: const Text('Stage'),
                onTap: () {
                  Navigator.pop(context);
                  cubit.stageFile(fileIdx);
                },
              ),
            // Unstage (only in Staged tab)
            if (isStaged)
              ListTile(
                leading: Icon(Icons.remove_circle_outline, color: cs.tertiary),
                title: const Text('Unstage'),
                onTap: () {
                  Navigator.pop(context);
                  cubit.unstageFile(fileIdx);
                },
              ),
            // Revert (only in Changes tab)
            if (!isStaged)
              ListTile(
                leading: Icon(Icons.undo, color: cs.error),
                title: const Text('Revert'),
                subtitle: const Text('Discard all changes in this file'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmRevert(
                    context,
                    title: 'この変更を破棄しますか',
                    message: 'このファイルの未ステージ変更をすべて破棄します。',
                    onConfirm: () => cubit.revertFile(fileIdx),
                  );
                },
              ),
            // Request Change (always available)
            ListTile(
              leading: Icon(Icons.rate_review_outlined, color: cs.secondary),
              title: const Text('Request Change'),
              subtitle: const Text('Send this file back to AI with feedback'),
              onTap: () {
                Navigator.pop(context);
                context.router.maybePop(
                  DiffSelection(diffText: reconstructUnifiedDiff(file)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showHunkActionSheet(
    BuildContext context,
    GitViewCubit cubit,
    GitViewState state,
    int fileIdx,
    int hunkIdx,
  ) {
    if (fileIdx >= state.files.length) return;
    final file = state.files[fileIdx];
    if (hunkIdx >= file.hunks.length) return;
    final hunk = file.hunks[hunkIdx];
    final cs = Theme.of(context).colorScheme;
    final isStaged = state.viewMode == GitViewMode.staged;

    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Text(
                file.filePath,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                hunk.header,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Theme.of(context).extension<AppColors>()!.subtleText,
                ),
              ),
            ),
            const Divider(height: 1),
            if (!isStaged)
              ListTile(
                leading: Icon(Icons.add_circle_outline, color: cs.primary),
                title: const Text('Stage'),
                onTap: () {
                  Navigator.pop(context);
                  cubit.stageHunk(fileIdx, hunkIdx);
                },
              ),
            if (isStaged)
              ListTile(
                leading: Icon(Icons.remove_circle_outline, color: cs.tertiary),
                title: const Text('Unstage'),
                onTap: () {
                  Navigator.pop(context);
                  cubit.unstageHunk(fileIdx, hunkIdx);
                },
              ),
            if (!isStaged)
              ListTile(
                leading: Icon(Icons.undo, color: cs.error),
                title: const Text('Revert'),
                subtitle: const Text('Discard changes in this hunk'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmRevert(
                    context,
                    title: 'この変更を破棄しますか',
                    message: 'このハンクの未ステージ変更を破棄します。',
                    onConfirm: () => cubit.revertHunk(fileIdx, hunkIdx),
                  );
                },
              ),
            ListTile(
              leading: Icon(Icons.rate_review_outlined, color: cs.secondary),
              title: const Text('Request Change'),
              subtitle: const Text('Send this hunk back to AI with feedback'),
              onTap: () {
                Navigator.pop(context);
                context.router.maybePop(
                  reconstructDiff(state.files, {'$fileIdx:$hunkIdx'}),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRevert(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revert'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onConfirm();
    }
  }
}

/// 2-tab segment: Changes (all) / Staged
class _GitViewModeSegment extends StatelessWidget {
  final GitViewMode viewMode;
  final ValueChanged<GitViewMode> onChanged;

  const _GitViewModeSegment({required this.viewMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SegmentedButton<GitViewMode>(
        segments: const [
          ButtonSegment(value: GitViewMode.unstaged, label: Text('Unstaged')),
          ButtonSegment(value: GitViewMode.staged, label: Text('Staged')),
        ],
        selected: {viewMode},
        onSelectionChanged: (s) => onChanged(s.first),
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// Bottom bar with diff summary stats and git action buttons (Pull / Commit / Push).
class _DiffBottomBar extends StatelessWidget {
  final GitViewState state;
  final GitViewCubit cubit;
  final VoidCallback onCommit;
  final VoidCallback onPull;
  final VoidCallback onPush;

  const _DiffBottomBar({
    required this.state,
    required this.cubit,
    required this.onCommit,
    required this.onPull,
    required this.onPush,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Calculate stats from visible files
    final files = state.files;
    var additions = 0;
    var deletions = 0;
    for (final f in files) {
      final s = f.stats;
      additions += s.added;
      deletions += s.removed;
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Stats row
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    if (files.isNotEmpty) ...[
                      Text(
                        '${files.length} files',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (additions > 0)
                        Text(
                          '+$additions',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      if (additions > 0 && deletions > 0)
                        const SizedBox(width: 4),
                      if (deletions > 0)
                        Text(
                          '-$deletions',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.error,
                          ),
                        ),
                    ],
                    const Spacer(),
                    // Remote status badges
                    if (state.fetching)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (state.hasUpstream && state.commitsBehind > 0)
                      _RemoteBadge(
                        icon: Icons.arrow_downward,
                        count: state.commitsBehind,
                        color: cs.tertiary,
                      ),
                    if (state.hasUpstream && state.commitsAhead > 0)
                      _RemoteBadge(
                        icon: Icons.arrow_upward,
                        count: state.commitsAhead,
                        color: cs.primary,
                      ),
                    if (state.hasUpstream &&
                        state.commitsAhead == 0 &&
                        state.commitsBehind == 0 &&
                        !state.fetching)
                      Icon(Icons.check, size: 14, color: cs.onSurfaceVariant),
                    if (!state.hasUpstream && !state.fetching)
                      Text(
                        'No upstream',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              // Action buttons row: Pull | Push | Commit
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      key: const ValueKey('pull_button'),
                      icon: Icons.download,
                      label: state.commitsBehind > 0
                          ? 'Pull (${state.commitsBehind})'
                          : 'Pull',
                      loading: state.pulling,
                      onPressed:
                          _isBusy ||
                              !state.hasUpstream ||
                              state.commitsBehind == 0
                          ? null
                          : onPull,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      key: const ValueKey('push_button'),
                      icon: Icons.upload,
                      label: state.commitsAhead > 0
                          ? 'Push (${state.commitsAhead})'
                          : 'Push',
                      loading: state.pushing,
                      onPressed: _isBusy || state.commitsAhead == 0
                          ? null
                          : onPush,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      key: const ValueKey('commit_button'),
                      icon: Icons.check,
                      label: 'Commit',
                      primary: true,
                      onPressed: _isBusy ? null : onCommit,
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

  bool get _isBusy => state.staging || state.pulling || state.pushing;
}

/// Small badge showing ↑N or ↓N for remote ahead/behind.
class _RemoteBadge extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;

  const _RemoteBadge({
    required this.icon,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 1),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Outlined action button used in the bottom bar.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool primary;

  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );

    final effectiveOnPressed = loading ? null : onPressed;
    const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 10);

    if (primary) {
      return FilledButton(
        onPressed: effectiveOnPressed,
        style: FilledButton.styleFrom(padding: padding),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: effectiveOnPressed,
      style: OutlinedButton.styleFrom(padding: padding),
      child: child,
    );
  }
}

/// Tappable branch name indicator in the AppBar bottom area.
class _BranchIndicator extends StatelessWidget {
  final String? branchName;
  final bool isWorktree;
  final String? projectPath;

  const _BranchIndicator({
    required this.branchName,
    required this.isWorktree,
    this.projectPath,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayName = branchName ?? '...';

    return GestureDetector(
      onTap: projectPath != null
          ? () => showBranchSelectorSheet(context, projectPath!)
          : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isWorktree ? Icons.fork_right : Icons.commit,
              size: 14,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            if (isWorktree) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'worktree',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: cs.onTertiaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                displayName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

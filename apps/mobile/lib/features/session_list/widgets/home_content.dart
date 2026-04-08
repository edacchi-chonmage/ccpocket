import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../constants/app_constants.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/messages.dart';
import '../../../services/app_update_service.dart';
import '../../../services/draft_service.dart';
import '../../../services/multi_bridge_manager.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/session_card.dart';
import '../state/session_list_cubit.dart';
import '../state/session_list_state.dart';
import 'section_header.dart';
import 'session_filter_bar.dart';
import 'session_list_empty_state.dart';
import 'app_update_banner.dart';
import 'bridge_update_banner.dart';
import 'session_reconnect_banner.dart';

class HomeContent extends StatefulWidget {
  final BridgeConnectionState connectionState;
  final String? bridgeVersion;
  final List<SessionInfo> sessions;
  final List<RecentSession> recentSessions;
  final Set<String> accumulatedProjectPaths;
  final String searchQuery;
  final bool isLoadingMore;
  final bool isInitialLoading;
  final bool hasMoreSessions;
  final Set<String> archivingSessionIds;
  final Set<String> unseenSessionIds;
  final List<HostBridgeStatus> hostStatuses;
  final String? selectedHostId;
  final ValueChanged<String?>? onSelectHost;
  final VoidCallback? onAddHost;
  final String? currentProjectFilter;
  final List<String> projectPaths;
  final VoidCallback onNewSession;
  final void Function(
    String sessionId, {
    String? hostId,
    String? projectPath,
    String? gitBranch,
    String? worktreePath,
    String? provider,
    String? permissionMode,
    String? sandboxMode,
  })
  onTapRunning;
  final void Function(String sessionId, {String? hostId}) onStopSession;
  final void Function(
    String sessionId,
    String toolUseId, {
    String? hostId,
    Map<String, dynamic>? updatedInput,
    bool clearContext,
  })?
  onApprovePermission;
  final void Function(String sessionId, String toolUseId, {String? hostId})?
  onApproveAlways;
  final void Function(
    String sessionId,
    String toolUseId, {
    String? hostId,
    String? message,
  })?
  onRejectPermission;
  final void Function(
    String sessionId,
    String toolUseId,
    String result, {
    String? hostId,
  })?
  onAnswerQuestion;
  final ValueChanged<RecentSession> onResumeSession;
  final ValueChanged<RecentSession> onLongPressRecentSession;
  final ValueChanged<RecentSession> onArchiveSession;
  final ValueChanged<SessionInfo> onLongPressRunningSession;
  final ValueChanged<String?> onSelectProject;
  final VoidCallback onLoadMore;
  final ProviderFilter providerFilter;
  final bool namedOnly;
  final VoidCallback onToggleProvider;
  final VoidCallback onToggleNamed;
  final AppUpdateInfo? appUpdateInfo;
  final VoidCallback? onDismissAppUpdate;

  const HomeContent({
    super.key,
    required this.connectionState,
    this.bridgeVersion,
    required this.sessions,
    required this.recentSessions,
    required this.accumulatedProjectPaths,
    required this.searchQuery,
    required this.isLoadingMore,
    required this.isInitialLoading,
    required this.hasMoreSessions,
    this.archivingSessionIds = const {},
    this.unseenSessionIds = const {},
    this.hostStatuses = const [],
    this.selectedHostId,
    this.onSelectHost,
    this.onAddHost,
    required this.currentProjectFilter,
    this.projectPaths = const [],
    required this.onNewSession,
    required this.onTapRunning,
    required this.onStopSession,
    this.onApprovePermission,
    this.onApproveAlways,
    this.onRejectPermission,
    this.onAnswerQuestion,
    required this.onResumeSession,
    required this.onLongPressRecentSession,
    required this.onArchiveSession,
    required this.onLongPressRunningSession,
    required this.onSelectProject,
    required this.onLoadMore,
    required this.providerFilter,
    required this.namedOnly,
    required this.onToggleProvider,
    required this.onToggleNamed,
    this.appUpdateInfo,
    this.onDismissAppUpdate,
  });

  @override
  State<HomeContent> createState() => HomeContentState();
}

class HomeContentState extends State<HomeContent> {
  bool _isSearching = false;
  bool _updateBannerDismissed = false;
  final _searchController = TextEditingController();
  SessionDisplayMode _displayMode = SessionDisplayMode.first;

  @override
  void initState() {
    super.initState();
    _loadDisplayMode();
  }

  Future<void> _loadDisplayMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString('session_list_display_mode');
    if (modeStr != null && mounted) {
      setState(() {
        _displayMode = SessionDisplayMode.values.firstWhere(
          (m) => m.name == modeStr,
          orElse: () => SessionDisplayMode.first,
        );
      });
    }
  }

  void _toggleDisplayMode() async {
    final next = switch (_displayMode) {
      SessionDisplayMode.first => SessionDisplayMode.last,
      SessionDisplayMode.last => SessionDisplayMode.summary,
      SessionDisplayMode.summary => SessionDisplayMode.first,
    };
    setState(() => _displayMode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('session_list_display_mode', next.name);
  }

  @override
  void didUpdateWidget(covariant HomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部から searchQuery がクリアされたら検索UIも閉じる
    if (widget.searchQuery.isEmpty && oldWidget.searchQuery.isNotEmpty) {
      setState(() => _isSearching = false);
      _searchController.clear();
    }
    // Reset dismiss state when reconnected (new bridgeVersion received)
    if (widget.bridgeVersion != oldWidget.bridgeVersion) {
      _updateBannerDismissed = false;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        context.read<SessionListCubit>().setSearchQuery('');
      }
    });
  }

  /// Open search field programmatically (e.g. from keyboard shortcut).
  void openSearch() {
    if (!_isSearching) {
      _toggleSearch();
    }
  }

  Widget? _buildAppUpdateBanner() {
    if (widget.appUpdateInfo == null) return null;
    return AppUpdateBanner(
      updateInfo: widget.appUpdateInfo!,
      onDismiss: widget.onDismissAppUpdate,
    );
  }

  Widget? _buildUpdateBanner() {
    if (_updateBannerDismissed) return null;
    if (!BridgeUpdateBanner.shouldShow(
      widget.bridgeVersion,
      AppConstants.expectedBridgeVersion,
    )) {
      return null;
    }
    return BridgeUpdateBanner(
      currentVersion: widget.bridgeVersion!,
      expectedVersion: AppConstants.expectedBridgeVersion,
      onDismiss: () => setState(() => _updateBannerDismissed = true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final appColors = Theme.of(context).extension<AppColors>()!;
    final isReconnecting =
        widget.connectionState == BridgeConnectionState.reconnecting;
    final updateBanner = _buildUpdateBanner();
    final appUpdateBanner = _buildAppUpdateBanner();

    // Compute derived state
    // Exclude running sessions from recent list to avoid duplicates
    final selectedHostId = widget.selectedHostId;
    final selectedHost = selectedHostId == null
        ? null
        : widget.hostStatuses
              .where((status) => status.hostId == selectedHostId)
              .firstOrNull;
    bool matchesSelectedHost({String? hostId, String? hostLabel}) {
      if (selectedHostId == null) {
        return true;
      }
      if (hostId == selectedHostId) {
        return true;
      }
      return selectedHost != null &&
          hostLabel != null &&
          hostLabel.isNotEmpty &&
          hostLabel == selectedHost.hostLabel;
    }

    final visibleRunningSessions = selectedHostId == null
        ? widget.sessions
        : widget.sessions
              .where(
                (session) => matchesSelectedHost(
                  hostId: session.hostId,
                  hostLabel: session.hostLabel,
                ),
              )
              .toList();
    final visibleRecentSessions = selectedHostId == null
        ? widget.recentSessions
        : widget.recentSessions
              .where(
                (session) => matchesSelectedHost(
                  hostId: session.hostId,
                  hostLabel: session.hostLabel,
                ),
              )
              .toList();
    final hasRunningSessions = visibleRunningSessions.isNotEmpty;
    final hasRecentSessions = visibleRecentSessions.isNotEmpty;
    final runningSessionIds = widget.sessions
        .expand(
          (s) => [
            _sessionKey(s.hostId, s.id),
            if (s.claudeSessionId != null)
              _sessionKey(s.hostId, s.claudeSessionId!),
          ],
        )
        .toSet();

    // Fallback for Codex sessions which use a short proxy ID instead of UUID
    bool isDuplicate(RecentSession rs) {
      if (runningSessionIds.contains(_sessionKey(rs.hostId, rs.sessionId))) {
        return true;
      }
      for (final s in visibleRunningSessions) {
        if (s.provider == rs.provider &&
            s.projectPath == rs.projectPath &&
            s.createdAt == rs.created &&
            s.hostId == rs.hostId) {
          return true;
        }
      }
      return false;
    }

    final filteredSessions = visibleRecentSessions
        .where((s) => !isDuplicate(s))
        .where(
          (s) =>
              widget.currentProjectFilter == null ||
              s.projectPath == widget.currentProjectFilter,
        )
        .where((s) {
          return switch (widget.providerFilter) {
            ProviderFilter.all => true,
            ProviderFilter.claude => s.provider != Provider.codex.value,
            ProviderFilter.codex => s.provider == Provider.codex.value,
          };
        })
        .where((s) => !widget.namedOnly || (s.name?.trim().isNotEmpty ?? false))
        .where((s) {
          if (widget.searchQuery.isEmpty) return true;
          final q = widget.searchQuery.toLowerCase();
          return (s.name?.toLowerCase().contains(q) ?? false) ||
              s.firstPrompt.toLowerCase().contains(q) ||
              (s.lastPrompt?.toLowerCase().contains(q) ?? false) ||
              (s.summary?.toLowerCase().contains(q) ?? false) ||
              (s.hostLabel?.toLowerCase().contains(q) ?? false);
        })
        .toList();
    final visibleProjects = {
      ...widget.projectPaths,
      ...widget.recentSessions.map((s) => s.projectPath),
      ...widget.sessions.map((s) => s.projectPath),
    }.toList()
      ..sort();

    final hasActiveFilter =
        selectedHostId != null ||
        widget.currentProjectFilter != null ||
        widget.providerFilter != ProviderFilter.all ||
        widget.namedOnly ||
        widget.searchQuery.isNotEmpty;

    if (!hasRunningSessions && !hasRecentSessions && !hasActiveFilter) {
      // Show skeleton while initial data is loading
      if (widget.isInitialLoading) {
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            if (isReconnecting) const SessionReconnectBanner(),
            ?updateBanner,
            ?appUpdateBanner,
            SectionHeader(
              icon: Icons.history,
              label: 'Recent Sessions',
              color: appColors.subtleText,
            ),
            const SizedBox(height: 8),
            const _SessionListSkeleton(),
          ],
        );
      }

      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (isReconnecting) const SessionReconnectBanner(),
          ?updateBanner,
          const SizedBox(height: 80),
          SessionListEmptyState(onNewSession: widget.onNewSession),
        ],
      );
    }

    return ListView(
      key: const ValueKey('session_list'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        if (isReconnecting) const SessionReconnectBanner(),
        ?updateBanner,
        if (widget.hostStatuses.isNotEmpty) ...[
          _HostTabs(
            hostStatuses: widget.hostStatuses,
            selectedHostId: selectedHostId,
            onSelectHost: widget.onSelectHost ?? (_) {},
            onAddHost: widget.onAddHost,
          ),
          const SizedBox(height: 12),
        ],
        if (selectedHost != null &&
            selectedHost.connectionState != BridgeConnectionState.connected) ...[
          _SelectedHostBanner(status: selectedHost),
          const SizedBox(height: 12),
        ],
        if (visibleRunningSessions.isNotEmpty) ...[
          SectionHeader(
            icon: Icons.play_circle_filled,
            label: 'Running',
            color: appColors.statusOnline,
          ),
          const SizedBox(height: 4),
          for (final session in visibleRunningSessions)
            Slidable(
              key: ValueKey(
                'running_session_${_sessionKey(session.hostId, session.id)}',
              ),
              endActionPane: ActionPane(
                motion: const BehindMotion(),
                extentRatio: 0.18,
                children: [
                  CustomSlidableAction(
                    onPressed: (_) => widget.onStopSession(
                      session.id,
                      hostId: session.hostId,
                    ),
                    backgroundColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.stop_circle_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
              child: RunningSessionCard(
                session: session,
                isUnseen: widget.unseenSessionIds.contains(
                  _sessionKey(session.hostId, session.id),
                ),
                onLongPress: () => widget.onLongPressRunningSession(session),
                onTap: () => widget.onTapRunning(
                  session.id,
                  hostId: session.hostId,
                  projectPath: session.projectPath,
                  gitBranch: session.worktreePath != null
                      ? session.worktreeBranch
                      : session.gitBranch,
                  worktreePath: session.worktreePath,
                  provider: session.provider,
                  permissionMode: session.permissionMode,
                  sandboxMode: session.codexSandboxMode,
                ),
                onApprove:
                    (
                      toolUseId, {
                      Map<String, dynamic>? updatedInput,
                      bool clearContext = false,
                    }) => widget.onApprovePermission?.call(
                      session.id,
                      toolUseId,
                      hostId: session.hostId,
                      updatedInput: updatedInput,
                      clearContext: clearContext,
                    ),
                onApproveAlways: (toolUseId) =>
                    widget.onApproveAlways?.call(
                      session.id,
                      toolUseId,
                      hostId: session.hostId,
                    ),
                onReject: (toolUseId, {String? message}) => widget
                    .onRejectPermission
                    ?.call(
                      session.id,
                      toolUseId,
                      hostId: session.hostId,
                      message: message,
                    ),
                onAnswer: (toolUseId, result) => widget.onAnswerQuestion?.call(
                  session.id,
                  toolUseId,
                  result,
                  hostId: session.hostId,
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
        if (widget.isInitialLoading ||
            hasRecentSessions ||
            hasActiveFilter) ...[
          SectionHeader(
            icon: Icons.history,
            label: 'Recent Sessions',
            color: appColors.subtleText,
            trailing: IconButton(
              key: const ValueKey('search_button'),
              icon: Icon(
                _isSearching ? Icons.close : Icons.search,
                size: 18,
                color: appColors.subtleText,
              ),
              onPressed: _toggleSearch,
              tooltip: 'Search',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (_isSearching) ...[
            const SizedBox(height: 4),
            TextField(
              key: const ValueKey('search_field'),
              controller: _searchController,
              autofocus: true,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                hintText: 'Search sessions...',
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: appColors.subtleText,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: appColors.subtleText.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: appColors.subtleText.withValues(alpha: 0.3),
                  ),
                ),
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (v) =>
                  context.read<SessionListCubit>().setSearchQuery(v),
            ),
          ],
          const SizedBox(height: 8),
          SessionFilterBar(
            displayMode: _displayMode,
            onToggleDisplayMode: _toggleDisplayMode,
            providerFilter: widget.providerFilter,
            onToggleProviderFilter: widget.onToggleProvider,
            projects: visibleProjects.map((path) {
              return (path: path, name: path.split('/').last);
            }).toList(),
            currentProjectFilter: widget.currentProjectFilter,
            onProjectFilterChanged: widget.onSelectProject,
            namedOnly: widget.namedOnly,
            onToggleNamed: widget.onToggleNamed,
          ),
          const SizedBox(height: 8),
          if (widget.isInitialLoading)
            const _SessionListSkeleton()
          else ...[
            if (filteredSessions.isEmpty)
              _RecentSessionsEmptyResult(
                title: hasActiveFilter
                    ? l.noSessionsMatchFilters
                    : l.noRecentSessions,
                subtitle: hasActiveFilter ? l.adjustFiltersAndSearch : null,
              )
            else
              for (final session in filteredSessions)
                Slidable(
                  key: ValueKey(
                    'recent_session_${_sessionKey(session.hostId, session.sessionId)}',
                  ),
                  endActionPane: ActionPane(
                    motion: const BehindMotion(),
                    extentRatio: 0.18,
                    children: [
                      CustomSlidableAction(
                        onPressed: (_) => widget.onArchiveSession(session),
                        backgroundColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.archive_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                  child: RecentSessionCard(
                    session: session,
                    displayMode: _displayMode,
                    draftText: context.read<DraftService>().getDraft(
                      _sessionKey(session.hostId, session.sessionId),
                    ),
                    isProcessing: widget.archivingSessionIds.contains(
                      _sessionKey(session.hostId, session.sessionId),
                    ),
                    onTap: () => widget.onResumeSession(session),
                    onLongPress: () => widget.onLongPressRecentSession(session),
                  ),
                ),
            if (widget.hasMoreSessions) ...[
              const SizedBox(height: 8),
              Center(
                child: widget.isLoadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton.icon(
                        key: const ValueKey('load_more_button'),
                        onPressed: widget.onLoadMore,
                        icon: const Icon(Icons.expand_more, size: 18),
                        label: const Text('Load More'),
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ],
    );
  }
}

String _sessionKey(String? hostId, String sessionId) =>
    hostId == null || hostId.isEmpty ? sessionId : '$hostId::$sessionId';

class _HostTabs extends StatelessWidget {
  const _HostTabs({
    required this.hostStatuses,
    required this.selectedHostId,
    required this.onSelectHost,
    this.onAddHost,
  });

  final List<HostBridgeStatus> hostStatuses;
  final String? selectedHostId;
  final ValueChanged<String?> onSelectHost;
  final VoidCallback? onAddHost;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('統合'),
              showCheckmark: false,
              selectedColor: colorScheme.primary,
              backgroundColor: colorScheme.surfaceContainerHigh,
              labelStyle: TextStyle(
                color: selectedHostId == null
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
              side: BorderSide(
                color: selectedHostId == null
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
              ),
              selected: selectedHostId == null,
              onSelected: (_) => onSelectHost(null),
            ),
          ),
          for (final status in hostStatuses)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HostStateDot(state: status.connectionState),
                    const SizedBox(width: 6),
                    Text(status.hostLabel),
                  ],
                ),
                showCheckmark: false,
                selectedColor: colorScheme.primary,
                backgroundColor: colorScheme.surfaceContainerHigh,
                labelStyle: TextStyle(
                  color: selectedHostId == status.hostId
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                side: BorderSide(
                  color: selectedHostId == status.hostId
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                ),
                selected: selectedHostId == status.hostId,
                onSelected: (_) => onSelectHost(status.hostId),
              ),
            ),
          if (onAddHost != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(
                  Icons.add,
                  size: 18,
                  color: colorScheme.onSurface,
                ),
                label: const Text('追加'),
                backgroundColor: colorScheme.surfaceContainerHigh,
                labelStyle: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                side: BorderSide(color: colorScheme.outlineVariant),
                onPressed: onAddHost,
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectedHostBanner extends StatelessWidget {
  const _SelectedHostBanner({required this.status});

  final HostBridgeStatus status;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final text = switch (status.connectionState) {
      BridgeConnectionState.connecting => 'Connecting to ${status.hostLabel}…',
      BridgeConnectionState.reconnecting =>
        'Reconnecting to ${status.hostLabel}…',
      BridgeConnectionState.disconnected => '${status.hostLabel} is offline',
      BridgeConnectionState.connected => null,
    };
    if (text == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: appColors.subtleText.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          _HostStateDot(state: status.connectionState),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HostStateDot extends StatelessWidget {
  const _HostStateDot({required this.state});

  final BridgeConnectionState state;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final color = switch (state) {
      BridgeConnectionState.connected => appColors.statusOnline,
      BridgeConnectionState.connecting => appColors.statusApproval,
      BridgeConnectionState.reconnecting => appColors.statusRunning,
      BridgeConnectionState.disconnected => appColors.subtleText,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _RecentSessionsEmptyResult extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _RecentSessionsEmptyResult({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Icon(Icons.filter_alt_off, color: appColors.subtleText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: appColors.subtleText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton placeholder that mimics a list of [RecentSessionCard] widgets.
///
/// Uses [Skeletonizer] to render dummy cards with a shimmer animation,
/// providing visual feedback while the initial session list is loading.
class _SessionListSkeleton extends StatelessWidget {
  const _SessionListSkeleton();

  static const _dummySessions = [
    RecentSession(
      sessionId: 'skeleton-1',
      firstPrompt: 'Implement the new feature for user authentication flow',
      created: '2025-01-01T00:00:00Z',
      modified: '2025-01-01T01:00:00Z',
      gitBranch: 'feat/auth',
      projectPath: '/projects/my-app',
      isSidechain: false,
    ),
    RecentSession(
      sessionId: 'skeleton-2',
      firstPrompt: 'Fix the CI pipeline build failure on main branch',
      created: '2025-01-01T00:00:00Z',
      modified: '2025-01-01T01:00:00Z',
      gitBranch: 'fix/ci',
      projectPath: '/projects/backend',
      isSidechain: false,
    ),
    RecentSession(
      sessionId: 'skeleton-3',
      firstPrompt: 'Add dark mode support to the settings page',
      created: '2025-01-01T00:00:00Z',
      modified: '2025-01-01T01:00:00Z',
      gitBranch: 'main',
      projectPath: '/projects/mobile',
      isSidechain: false,
    ),
    RecentSession(
      sessionId: 'skeleton-4',
      firstPrompt: 'Refactor database queries for better performance',
      created: '2025-01-01T00:00:00Z',
      modified: '2025-01-01T01:00:00Z',
      gitBranch: 'perf/db',
      projectPath: '/projects/api',
      isSidechain: false,
    ),
    RecentSession(
      sessionId: 'skeleton-5',
      firstPrompt: 'Update documentation for the REST API endpoints',
      created: '2025-01-01T00:00:00Z',
      modified: '2025-01-01T01:00:00Z',
      gitBranch: 'docs',
      projectPath: '/projects/docs',
      isSidechain: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      child: Column(
        children: [
          for (final session in _dummySessions)
            RecentSessionCard(session: session, onTap: () {}),
        ],
      ),
    );
  }
}

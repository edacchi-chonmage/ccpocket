import 'dart:async';

import 'package:ccpocket/features/session_list/state/session_list_cubit.dart';
import 'package:ccpocket/features/session_list/state/session_list_state.dart';
import 'package:ccpocket/features/session_list/widgets/home_content.dart';
import 'package:ccpocket/models/machine.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/services/draft_service.dart';
import 'package:ccpocket/services/multi_bridge_manager.dart';
import 'package:ccpocket/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skeletonizer/src/widgets/skeletonizer.dart';

class _FakeMachineSource implements MultiBridgeMachineSource {
  @override
  List<Machine> get currentMachines => const [];

  @override
  Future<String?> getApiKey(String machineId) async => null;

  @override
  Stream<List<MachineWithStatus>> get machines =>
      const Stream<List<MachineWithStatus>>.empty();
}

RecentSession _session({
  required String id,
  String projectPath = '/home/user/project-a',
}) {
  return RecentSession(
    sessionId: id,
    firstPrompt: 'test prompt for $id',
    created: '2025-01-01T00:00:00Z',
    modified: '2025-01-01T00:00:00Z',
    gitBranch: 'main',
    projectPath: projectPath,
    isSidechain: false,
  );
}

SessionInfo _runningSession({required String id}) {
  return SessionInfo.fromJson({
    'id': id,
    'projectPath': '/home/user/project-a',
    'status': 'running',
    'createdAt': '2025-01-01T12:00:00Z',
    'lastActivityAt': '2025-01-01T12:00:00Z',
    'gitBranch': 'main',
    'lastMessage': 'Working on something',
    'messageCount': 1,
  });
}

Widget _buildHomeContent({
  List<SessionInfo> sessions = const [],
  List<RecentSession> recentSessions = const [],
  List<HostBridgeStatus> hostStatuses = const [],
  String? selectedHostId,
  bool isInitialLoading = false,
  VoidCallback? onAddHost,
  required SessionListCubit cubit,
  required DraftService draftService,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: MultiBlocProvider(
        providers: [BlocProvider<SessionListCubit>.value(value: cubit)],
        child: RepositoryProvider<DraftService>.value(
          value: draftService,
          child: HomeContent(
            connectionState: BridgeConnectionState.connected,
            sessions: sessions,
            recentSessions: recentSessions,
            accumulatedProjectPaths: const {},
            searchQuery: '',
            isLoadingMore: false,
            isInitialLoading: isInitialLoading,
            hasMoreSessions: false,
            hostStatuses: hostStatuses,
            selectedHostId: selectedHostId,
            onSelectHost: (_) {},
            onAddHost: onAddHost,
            currentProjectFilter: null,
            onNewSession: () {},
            onTapRunning:
                (
                  id, {
                  hostId,
                  projectPath,
                  gitBranch,
                  worktreePath,
                  provider,
                  permissionMode,
                  sandboxMode,
                }) {},
            onStopSession: (_, {hostId}) {},
            onResumeSession: (_) {},
            onLongPressRecentSession: (_) {},
            onArchiveSession: (_) {},
            onLongPressRunningSession: (_) {},
            onSelectProject: (_) {},
            onLoadMore: () {},
            providerFilter: ProviderFilter.all,
            namedOnly: false,
            onToggleProvider: () {},
            onToggleNamed: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  late MultiBridgeManager bridgeManager;
  late SessionListCubit cubit;
  late DraftService draftService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    draftService = DraftService(prefs);
    bridgeManager = MultiBridgeManager(machineSource: _FakeMachineSource());
    cubit = SessionListCubit(bridgeManager: bridgeManager);
  });

  tearDown(() {
    cubit.close();
    bridgeManager.close();
  });

  group('HomeContent skeleton', () {
    testWidgets('shows Skeletonizer when isInitialLoading is true and '
        'no sessions exist', (tester) async {
      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: const [],
          isInitialLoading: true,
          cubit: cubit,
          draftService: draftService,
        ),
      );
      await tester.pump();

      // Skeletonizer internally renders as _Skeletonizer + SkeletonizerScope.
      // Use SkeletonizerScope to detect presence.
      expect(find.byType(SkeletonizerScope), findsOneWidget);
      // Section header should say "Recent Sessions"
      expect(find.text('Recent Sessions'), findsOneWidget);
    });

    testWidgets('shows empty state when isInitialLoading is false and '
        'no sessions exist', (tester) async {
      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: const [],
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
        ),
      );
      await tester.pump();

      // Skeletonizer should NOT be present
      expect(find.byType(SkeletonizerScope), findsNothing);
      // Empty state should show the "New Session" button
      expect(find.text('New Session'), findsOneWidget);
    });

    testWidgets('shows real session cards (not skeleton) when sessions exist '
        'and isInitialLoading is false', (tester) async {
      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: [
            _session(id: 's1'),
            _session(id: 's2'),
          ],
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
        ),
      );
      await tester.pump();

      // No skeleton
      expect(find.byType(SkeletonizerScope), findsNothing);
      // Real session cards should be visible
      expect(find.text('test prompt for s1'), findsOneWidget);
      expect(find.text('test prompt for s2'), findsOneWidget);
    });

    testWidgets('shows host tabs including unified tab', (tester) async {
      final hostStatuses = [
        HostBridgeStatus(
          hostId: 'host-a',
          hostLabel: 'Host A',
          machine: const Machine(id: 'host-a', host: 'host-a.local'),
          connectionState: BridgeConnectionState.connected,
          bridge: BridgeService(),
        ),
        HostBridgeStatus(
          hostId: 'host-b',
          hostLabel: 'Host B',
          machine: const Machine(id: 'host-b', host: 'host-b.local'),
          connectionState: BridgeConnectionState.disconnected,
          bridge: BridgeService(),
        ),
      ];

      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: [_session(id: 's1')],
          hostStatuses: hostStatuses,
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
        ),
      );
      await tester.pump();

      expect(find.text('統合'), findsOneWidget);
      expect(find.text('Host A'), findsOneWidget);
      expect(find.text('Host B'), findsOneWidget);
    });

    testWidgets('shows add-host tab and triggers callback', (tester) async {
      var addTapped = false;
      final hostStatuses = [
        HostBridgeStatus(
          hostId: 'host-a',
          hostLabel: 'Host A',
          machine: const Machine(id: 'host-a', host: 'host-a.local'),
          connectionState: BridgeConnectionState.connected,
          bridge: BridgeService(),
        ),
      ];

      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: [_session(id: 's1')],
          hostStatuses: hostStatuses,
          isInitialLoading: false,
          onAddHost: () => addTapped = true,
          cubit: cubit,
          draftService: draftService,
        ),
      );
      await tester.pump();

      expect(find.text('追加'), findsOneWidget);
      final addChip = find.byType(ActionChip);
      await tester.ensureVisible(addChip);
      await tester.tap(addChip);
      await tester.pump();
      expect(addTapped, isTrue);
    });

    testWidgets('host tab shows running sessions even when local machine id differs '
        'but host label matches', (tester) async {
      final hostStatuses = [
        HostBridgeStatus(
          hostId: 'saved-host-id',
          hostLabel: 'Host A',
          machine: const Machine(id: 'saved-host-id', host: 'host-a.local'),
          connectionState: BridgeConnectionState.connected,
          bridge: BridgeService(),
        ),
      ];
      final sessions = [
        SessionInfo.fromJson({
          'id': 'r1',
          'projectPath': '/home/user/project-a',
          'status': 'running',
          'createdAt': '2025-01-01T12:00:00Z',
          'lastActivityAt': '2025-01-01T12:00:00Z',
          'gitBranch': 'main',
          'lastMessage': 'Working on something',
          'messageCount': 1,
          'hostId': 'different-runtime-id',
          'hostLabel': 'Host A',
        }),
      ];

      await tester.pumpWidget(
        _buildHomeContent(
          sessions: sessions,
          hostStatuses: hostStatuses,
          selectedHostId: 'saved-host-id',
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
        ),
      );
      await tester.pump();

      expect(find.text('Working on something'), findsOneWidget);
    });

    testWidgets('shows skeleton below running sessions when '
        'isInitialLoading is true', (tester) async {
      await tester.pumpWidget(
        _buildHomeContent(
          sessions: [_runningSession(id: 'r1')],
          recentSessions: const [],
          isInitialLoading: true,
          cubit: cubit,
          draftService: draftService,
        ),
      );
      await tester.pump();

      // Running session section should be visible
      expect(find.text('Running'), findsAtLeast(1));
      // Skeleton should show for recent sessions section
      expect(find.byType(SkeletonizerScope), findsOneWidget);
      expect(find.text('Recent Sessions'), findsOneWidget);
    });

    testWidgets('shows real recent sessions (not skeleton) below running '
        'sessions when loaded', (tester) async {
      await tester.pumpWidget(
        _buildHomeContent(
          sessions: [_runningSession(id: 'r1')],
          recentSessions: [_session(id: 's1')],
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
        ),
      );
      await tester.pump();

      // Running section visible
      expect(find.text('Running'), findsAtLeast(1));
      // No skeleton
      expect(find.byType(SkeletonizerScope), findsNothing);
      // Real recent session visible
      expect(find.text('test prompt for s1'), findsOneWidget);
    });

    testWidgets('shows skeleton while loading even if recent sessions exist', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: [_session(id: 's1')],
          isInitialLoading: true,
          cubit: cubit,
          draftService: draftService,
        ),
      );
      await tester.pump();

      // While loading, skeleton should be preferred over stale cards.
      expect(find.byType(SkeletonizerScope), findsOneWidget);
      expect(find.text('test prompt for s1'), findsNothing);
    });
  });
}

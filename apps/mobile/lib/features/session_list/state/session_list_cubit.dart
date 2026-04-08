import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/machine.dart';
import '../../../models/messages.dart';
import '../../../services/bridge_service.dart';
import '../../../services/multi_bridge_manager.dart';
import 'session_list_state.dart';

class _EmptyMachineSource implements MultiBridgeMachineSource {
  @override
  List<Machine> get currentMachines => const [];

  @override
  Future<String?> getApiKey(String machineId) async => null;

  @override
  Stream<List<MachineWithStatus>> get machines => const Stream.empty();
}

/// Manages session list state: sessions, filters, pagination, and
/// accumulated project paths.
///
/// All filters (project, provider, namedOnly, searchQuery) are applied
/// server-side. Filter changes trigger a re-fetch from offset 0 with
/// a skeleton loading state.
class SessionListCubit extends Cubit<SessionListState> {
  final MultiBridgeManager _bridgeManager;
  StreamSubscription<List<RecentSession>>? _recentSessionsSub;
  StreamSubscription<List<String>>? _projectHistorySub;
  Timer? _searchDebounce;

  SessionListCubit({
    MultiBridgeManager? bridgeManager,
    BridgeService? bridge,
  }) : _bridgeManager =
           bridgeManager ??
           MultiBridgeManager(
             machineSource: _EmptyMachineSource(),
             bridgeFactory: () => bridge ?? BridgeService(),
           ),
      super(const SessionListState()) {
    _recentSessionsSub = _bridgeManager.recentSessionsStream.listen((sessions) {
      final nextProjectPaths = {
        ...state.accumulatedProjectPaths,
        ...sessions.map((session) => session.projectPath),
      };
      emit(
        state.copyWith(
          sessions: sessions,
          accumulatedProjectPaths: nextProjectPaths,
          isInitialLoading: false,
          isLoadingMore: false,
          hasMore: false,
        ),
      );
    });
    _projectHistorySub = _bridgeManager.projectHistoryStream.listen((paths) {
      emit(
        state.copyWith(
          accumulatedProjectPaths: {
            ...state.accumulatedProjectPaths,
            ...paths,
          },
        ),
      );
    });
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final providerStr = prefs.getString('session_list_provider');
    final namedOnly = prefs.getBool('session_list_named_only');

    var provider = ProviderFilter.all;
    if (providerStr == ProviderFilter.claude.name) {
      provider = ProviderFilter.claude;
    } else if (providerStr == ProviderFilter.codex.name) {
      provider = ProviderFilter.codex;
    }

    emit(
      state.copyWith(providerFilter: provider, namedOnly: namedOnly ?? false),
    );
  }

  // ---- Filter commands (client-side only) ----

  /// Switch project filter. Resets sessions on the server side and fetches
  /// from offset 0 for the selected project.
  void selectProject(String? projectPath) {
    emit(state.copyWith(currentProjectFilter: projectPath));
  }

  /// Set search query with debounce for smoother UI typing.
  void setSearchQuery(String query) {
    emit(state.copyWith(searchQuery: query));
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (isClosed) return;
      emit(state.copyWith(searchQuery: query));
    });
  }

  /// Toggle provider filter: All → Codex → Claude → All.
  void toggleProviderFilter() async {
    final next = switch (state.providerFilter) {
      ProviderFilter.all => ProviderFilter.codex,
      ProviderFilter.codex => ProviderFilter.claude,
      ProviderFilter.claude => ProviderFilter.all,
    };
    emit(state.copyWith(providerFilter: next));
    // Persist preference in background (fire-and-forget).
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString('session_list_provider', next.name),
    );
  }

  /// Toggle named-only filter on/off.
  void toggleNamedOnly() async {
    final next = !state.namedOnly;
    emit(state.copyWith(namedOnly: next));
    // Persist preference in background (fire-and-forget).
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setBool('session_list_named_only', next),
    );
  }

  /// Load more sessions (pagination).
  void loadMore() {}

  /// Request fresh data from the server.
  void refresh() {
    emit(state.copyWith(isInitialLoading: true));
    _bridgeManager.requestRefreshAll();
  }

  /// Reset all filter state (used on disconnect).
  void resetFilters() {
    _searchDebounce?.cancel();
    emit(
      state.copyWith(
        sessions: const [],
        searchQuery: '',
        accumulatedProjectPaths: const {},
        isLoadingMore: false,
        isInitialLoading: false,
        providerFilter: ProviderFilter.all,
        namedOnly: false,
        currentProjectFilter: null,
      ),
    );
  }

  /// Optimistically update a session's name in the local state.
  void updateSessionName(String sessionId, String? name) {
    final updated = state.sessions.map((s) {
      if (s.sessionId == sessionId) {
        return name == null
            ? s.copyWithName(clearName: true)
            : s.copyWithName(name: name);
      }
      return s;
    }).toList();
    emit(state.copyWith(sessions: updated));
  }

  @override
  Future<void> close() {
    _searchDebounce?.cancel();
    _recentSessionsSub?.cancel();
    _projectHistorySub?.cancel();
    return super.close();
  }
}

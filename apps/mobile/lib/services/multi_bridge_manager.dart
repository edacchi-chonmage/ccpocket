import 'dart:async';

import '../models/machine.dart';
import '../models/messages.dart';
import 'bridge_service.dart';
import 'machine_manager_service.dart';

abstract class MultiBridgeMachineSource {
  Stream<List<MachineWithStatus>> get machines;
  List<Machine> get currentMachines;
  Future<String?> getApiKey(String machineId);
}

class MachineManagerBridgeSource implements MultiBridgeMachineSource {
  const MachineManagerBridgeSource(this._service);

  final MachineManagerService _service;

  @override
  Stream<List<MachineWithStatus>> get machines => _service.machines;

  @override
  List<Machine> get currentMachines => _service.currentMachines;

  @override
  Future<String?> getApiKey(String machineId) => _service.getApiKey(machineId);
}

class HostBridgeStatus {
  const HostBridgeStatus({
    required this.hostId,
    required this.hostLabel,
    required this.machine,
    required this.connectionState,
    required this.bridge,
    this.bridgeVersion,
  });

  final String hostId;
  final String hostLabel;
  final Machine machine;
  final BridgeConnectionState connectionState;
  final BridgeService bridge;
  final String? bridgeVersion;
}

class MultiBridgeManager {
  MultiBridgeManager({
    required MultiBridgeMachineSource machineSource,
    BridgeService Function()? bridgeFactory,
  }) : _machineSource = machineSource,
       _bridgeFactory = bridgeFactory ?? BridgeService.new {
    _machinesSub = _machineSource.machines.listen(_syncMachines);
    _syncMachines(
      _machineSource.currentMachines
          .map((machine) => MachineWithStatus(machine: machine))
          .toList(),
    );
  }

  final MultiBridgeMachineSource _machineSource;
  final BridgeService Function() _bridgeFactory;

  final _connectionController =
      StreamController<BridgeConnectionState>.broadcast();
  final _sessionListController = StreamController<List<SessionInfo>>.broadcast();
  final _recentSessionsController =
      StreamController<List<RecentSession>>.broadcast();
  final _projectHistoryController = StreamController<List<String>>.broadcast();
  final _hostStatusController =
      StreamController<List<HostBridgeStatus>>.broadcast();
  final _messageController =
      StreamController<({String hostId, ServerMessage message})>.broadcast();

  final Map<String, BridgeService> _bridges = {};
  final Map<String, Machine> _machines = {};
  final Map<String, MachineWithStatus> _machineStatuses = {};
  final Map<String, BridgeConnectionState> _connectionStates = {};
  final Map<String, List<SessionInfo>> _hostSessions = {};
  final Map<String, List<RecentSession>> _hostRecentSessions = {};
  final Map<String, List<String>> _hostProjectHistory = {};
  final Map<String, List<StreamSubscription<dynamic>>> _hostSubscriptions = {};

  StreamSubscription<List<MachineWithStatus>>? _machinesSub;

  Stream<BridgeConnectionState> get connectionStatus =>
      _connectionController.stream;
  Stream<List<SessionInfo>> get sessionList => _sessionListController.stream;
  Stream<List<RecentSession>> get recentSessionsStream =>
      _recentSessionsController.stream;
  Stream<List<String>> get projectHistoryStream =>
      _projectHistoryController.stream;
  Stream<List<HostBridgeStatus>> get hostStatuses => _hostStatusController.stream;
  Stream<({String hostId, ServerMessage message})> get messages =>
      _messageController.stream;

  List<HostBridgeStatus> get currentHostStatuses => _orderedHostIds
      .map((hostId) => HostBridgeStatus(
            hostId: hostId,
            hostLabel: _hostLabelFor(hostId),
            machine: _machines[hostId]!,
            connectionState:
                _connectionStates[hostId] ?? BridgeConnectionState.disconnected,
            bridge: _bridges[hostId]!,
            bridgeVersion: _bridges[hostId]!.bridgeVersion,
          ))
      .toList();

  List<String> get _orderedHostIds => _machineSource.currentMachines
      .map((machine) => machine.id)
      .where(_bridges.containsKey)
      .toList();

  BridgeService? bridgeForHost(String hostId) => _bridges[hostId];

  Future<void> connectAll() async {
    for (final machine in _machineSource.currentMachines) {
      await connectHost(machine.id);
    }
  }

  Future<void> connectHost(String hostId) async {
    final machine = _machines[hostId];
    final bridge = _bridges[hostId];
    if (machine == null || bridge == null) return;
    final apiKey = await _machineSource.getApiKey(hostId);
    final connectUrl = _buildWsUrl(machine, apiKey);
    bridge.connect(connectUrl);
  }

  void disconnectHost(String hostId) {
    _bridges[hostId]?.disconnect();
  }

  void ensureConnectedAll() {
    for (final bridge in _bridges.values) {
      bridge.ensureConnected();
    }
  }

  void requestRefreshAll() {
    for (final bridge in _bridges.values) {
      bridge.requestSessionList();
      bridge.requestRecentSessions();
      bridge.requestProjectHistory();
    }
  }

  Future<void> close() async {
    await _machinesSub?.cancel();
    for (final subs in _hostSubscriptions.values) {
      for (final sub in subs) {
        await sub.cancel();
      }
    }
    for (final bridge in _bridges.values) {
      bridge.disconnect();
    }
    await _connectionController.close();
    await _sessionListController.close();
    await _recentSessionsController.close();
    await _projectHistoryController.close();
    await _hostStatusController.close();
    await _messageController.close();
  }

  void _syncMachines(List<MachineWithStatus> statuses) {
    final nextIds = statuses.map((status) => status.machine.id).toSet();
    final currentIds = _bridges.keys.toSet();

    for (final removedId in currentIds.difference(nextIds)) {
      _disposeHost(removedId);
    }

    for (final status in statuses) {
      final machine = status.machine;
      _machines[machine.id] = machine;
      _machineStatuses[machine.id] = status;
      if (_bridges.containsKey(machine.id)) continue;
      final bridge = _bridgeFactory();
      _bridges[machine.id] = bridge;
      _attachHost(machine.id, bridge);
      unawaited(connectHost(machine.id));
    }

    _emitSnapshots();
  }

  void _attachHost(String hostId, BridgeService bridge) {
    _connectionStates[hostId] = BridgeConnectionState.disconnected;
    _hostSessions[hostId] = const [];
    _hostRecentSessions[hostId] = const [];
    _hostProjectHistory[hostId] = const [];

    _hostSubscriptions[hostId] = [
      bridge.connectionStatus.listen((state) {
        _connectionStates[hostId] = state;
        _emitSnapshots();
      }),
      bridge.sessionList.listen((sessions) {
        _hostSessions[hostId] = sessions
            .map(
              (session) => session.copyWithHost(
                hostId: hostId,
                hostLabel: _hostLabelFor(hostId),
              ),
            )
            .toList();
        _emitSnapshots();
      }),
      bridge.recentSessionsStream.listen((sessions) {
        _hostRecentSessions[hostId] = sessions
            .map(
              (session) => session.copyWithHost(
                hostId: hostId,
                hostLabel: _hostLabelFor(hostId),
              ),
            )
            .toList();
        _emitSnapshots();
      }),
      bridge.projectHistoryStream.listen((projects) {
        _hostProjectHistory[hostId] = projects;
        _emitSnapshots();
      }),
      bridge.messages.listen((message) {
        _messageController.add((hostId: hostId, message: message));
      }),
    ];
  }

  void _disposeHost(String hostId) {
    for (final sub in _hostSubscriptions.remove(hostId) ?? const []) {
      unawaited(sub.cancel());
    }
    _bridges.remove(hostId)?.disconnect();
    _machines.remove(hostId);
    _machineStatuses.remove(hostId);
    _connectionStates.remove(hostId);
    _hostSessions.remove(hostId);
    _hostRecentSessions.remove(hostId);
    _hostProjectHistory.remove(hostId);
  }

  void _emitSnapshots() {
    final mergedSessions = _hostSessions.values
        .expand((sessions) => sessions)
        .toList()
      ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
    final mergedRecentSessions = _hostRecentSessions.values
        .expand((sessions) => sessions)
        .toList()
      ..sort((a, b) => b.modified.compareTo(a.modified));
    final mergedProjects = _hostProjectHistory.values
        .expand((projects) => projects)
        .toSet()
        .toList()
      ..sort();

    _sessionListController.add(mergedSessions);
    _recentSessionsController.add(mergedRecentSessions);
    _projectHistoryController.add(mergedProjects);
    _connectionController.add(_aggregateConnectionState());
    _hostStatusController.add(currentHostStatuses);
  }

  BridgeConnectionState _aggregateConnectionState() {
    final states = _connectionStates.values.toList();
    if (states.contains(BridgeConnectionState.connected)) {
      return BridgeConnectionState.connected;
    }
    if (states.contains(BridgeConnectionState.reconnecting)) {
      return BridgeConnectionState.reconnecting;
    }
    if (states.contains(BridgeConnectionState.connecting)) {
      return BridgeConnectionState.connecting;
    }
    return BridgeConnectionState.disconnected;
  }

  String _buildWsUrl(Machine machine, String? apiKey) {
    final trimmedApiKey = apiKey?.trim() ?? '';
    if (trimmedApiKey.isEmpty) return machine.wsUrl;
    return '${machine.wsUrl}?token=$trimmedApiKey';
  }

  String _hostLabelFor(String hostId) =>
      _machines[hostId]?.displayName ?? hostId;
}

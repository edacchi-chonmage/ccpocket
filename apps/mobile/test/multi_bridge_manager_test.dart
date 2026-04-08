import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ccpocket/models/machine.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/services/multi_bridge_manager.dart';

class _FakeMachineSource implements MultiBridgeMachineSource {
  final _controller = StreamController<List<MachineWithStatus>>.broadcast();
  final Map<String, String?> _apiKeys;
  List<Machine> _machines;

  _FakeMachineSource(this._machines, {Map<String, String?> apiKeys = const {}})
    : _apiKeys = apiKeys;

  @override
  Stream<List<MachineWithStatus>> get machines => _controller.stream;

  @override
  List<Machine> get currentMachines => _machines;

  @override
  Future<String?> getApiKey(String machineId) async => _apiKeys[machineId];

  void emitMachines(List<Machine> machines) {
    _machines = machines;
    _controller.add(machines.map((machine) => MachineWithStatus(machine: machine)).toList());
  }

  Future<void> close() => _controller.close();
}

class _FakeBridgeService extends BridgeService {
  final connectionController =
      StreamController<BridgeConnectionState>.broadcast();
  final sessionsController = StreamController<List<SessionInfo>>.broadcast();
  final recentController = StreamController<List<RecentSession>>.broadcast();
  final projectHistoryController = StreamController<List<String>>.broadcast();
  final messageController = StreamController<ServerMessage>.broadcast();

  String? connectedUrl;
  bool disconnected = false;

  @override
  Stream<BridgeConnectionState> get connectionStatus => connectionController.stream;

  @override
  Stream<List<SessionInfo>> get sessionList => sessionsController.stream;

  @override
  Stream<List<RecentSession>> get recentSessionsStream => recentController.stream;

  @override
  Stream<List<String>> get projectHistoryStream => projectHistoryController.stream;

  @override
  Stream<ServerMessage> get messages => messageController.stream;

  @override
  void connect(String url) {
    connectedUrl = url;
  }

  @override
  void disconnect() {
    disconnected = true;
  }
}

void main() {
  group('MultiBridgeManager', () {
    test('connects all saved hosts and aggregates sessions with host labels', () async {
      final machineA = Machine(id: 'a', host: 'host-a', name: 'Mac A');
      final machineB = Machine(id: 'b', host: 'host-b', port: 9000, name: 'Mac B');
      final source = _FakeMachineSource([machineA, machineB], apiKeys: {'b': 'secret'});
      final bridges = <_FakeBridgeService>[];
      final manager = MultiBridgeManager(
        machineSource: source,
        bridgeFactory: () {
          final bridge = _FakeBridgeService();
          bridges.add(bridge);
          return bridge;
        },
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridges, hasLength(2));
      expect(bridges[0].connectedUrl, 'ws://host-a:8765');
      expect(bridges[1].connectedUrl, 'ws://host-b:9000?token=secret');

      final aggregatedSessionsFuture = manager.sessionList.firstWhere(
        (sessions) => sessions.any((session) => session.hostId == 'a'),
      );
      final aggregatedRecentSessionsFuture = manager.recentSessionsStream
          .firstWhere((sessions) => sessions.any((session) => session.hostId == 'b'));

      bridges[0].sessionsController.add([
        const SessionInfo(
          id: 's-a',
          provider: 'claude',
          projectPath: '/tmp/a',
          status: 'running',
          createdAt: '2026-01-01T00:00:00Z',
          lastActivityAt: '2026-01-01T00:00:01Z',
        ),
      ]);
      bridges[1].recentController.add([
        const RecentSession(
          sessionId: 'r-b',
          provider: 'codex',
          firstPrompt: 'hello',
          created: '2026-01-01T00:00:00Z',
          modified: '2026-01-01T00:00:02Z',
          gitBranch: 'main',
          projectPath: '/tmp/b',
          isSidechain: false,
        ),
      ]);

      final aggregatedSessions = await aggregatedSessionsFuture;
      final aggregatedRecentSessions = await aggregatedRecentSessionsFuture;

      expect(aggregatedSessions, contains(isA<SessionInfo>()
          .having((s) => s.hostId, 'hostId', 'a')
          .having((s) => s.hostLabel, 'hostLabel', 'Mac A')));
      expect(aggregatedRecentSessions, contains(isA<RecentSession>()
          .having((s) => s.hostId, 'hostId', 'b')
          .having((s) => s.hostLabel, 'hostLabel', 'Mac B')));

      await manager.close();
      await source.close();
    });
  });
}

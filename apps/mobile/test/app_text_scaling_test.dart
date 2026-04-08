import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ccpocket/features/session_list/state/session_list_cubit.dart';
import 'package:ccpocket/features/settings/state/settings_cubit.dart';
import 'package:ccpocket/main.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/providers/bridge_cubits.dart';
import 'package:ccpocket/providers/server_discovery_cubit.dart';
import 'package:ccpocket/services/bridge_service.dart';

void main() {
  testWidgets('app composes OS text scale with app text scale', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final bridge = BridgeService();

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: RepositoryProvider<BridgeService>.value(
          value: bridge,
          child: MultiBlocProvider(
            providers: [
              BlocProvider(create: (_) => SettingsCubit(prefs)),
              BlocProvider(
                create: (_) => ConnectionCubit(
                  BridgeConnectionState.disconnected,
                  bridge.connectionStatus,
                ),
              ),
              BlocProvider(
                create: (_) => ActiveSessionsCubit(const [], bridge.sessionList),
              ),
              BlocProvider(
                create: (_) =>
                    RecentSessionsCubit(const [], bridge.recentSessionsStream),
              ),
              BlocProvider(
                create: (_) => GalleryCubit(const [], bridge.galleryStream),
              ),
              BlocProvider(
                create: (_) => FileListCubit(const [], bridge.fileList),
              ),
              BlocProvider(
                create: (_) => ProjectHistoryCubit(
                  const [],
                  bridge.projectHistoryStream,
                ),
              ),
              BlocProvider(create: (_) => ServerDiscoveryCubit()),
              BlocProvider(
                create: (ctx) =>
                    SessionListCubit(bridge: ctx.read<BridgeService>()),
              ),
            ],
            child: const CcpocketApp(),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 4));

    final mediaQueries = tester
        .widgetList<MediaQuery>(find.byType(MediaQuery))
        .map((widget) => widget.data.textScaler.scale(10))
        .toList();

    expect(
      mediaQueries.any((scale) => (scale - 14.95).abs() < 0.01),
      isTrue,
    );
  });
}

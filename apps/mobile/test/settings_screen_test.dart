import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ccpocket/features/settings/settings_screen.dart';
import 'package:ccpocket/features/settings/state/settings_cubit.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/services/bridge_service.dart';

void main() {
  testWidgets('shows text size setting in general section', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      RepositoryProvider<BridgeService>.value(
        value: BridgeService(),
        child: BlocProvider(
          create: (_) => SettingsCubit(prefs),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const SettingsScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Text size'), findsOneWidget);
  });
}

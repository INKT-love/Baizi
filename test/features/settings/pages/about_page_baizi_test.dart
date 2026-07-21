import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:Baizi/core/providers/update_provider.dart';
import 'package:Baizi/core/providers/settings_provider.dart';
import 'package:Baizi/features/settings/pages/about_page.dart';
import 'package:Baizi/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows Baizi release status and upstream attribution', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'Baizi',
      packageName: 'top.inktandwkx.baizi',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(),
          ),
          ChangeNotifierProvider<UpdateProvider>(
            create: (_) => UpdateProvider(releaseManifestUrl: null),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AboutPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Show Updates'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Baizi'), findsWidgets);
    expect(find.text('AGPL-3.0'), findsOneWidget);
    expect(find.text('Website'), findsNothing);
  });

  testWidgets('shows the available-update status', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Baizi',
      packageName: 'top.inktandwkx.baizi',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final updates = UpdateProvider(
      client: MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {
            'location':
                'https://github.com/INKT-love/Baizi/releases/tag/v1.1.0',
          },
        ),
      ),
      currentVersionLoader: () async => '1.0.0',
    );
    await updates.checkForUpdates();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(),
          ),
          ChangeNotifierProvider<UpdateProvider>.value(value: updates),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AboutPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/update_provider.dart';
import 'package:Kelivo/features/settings/pages/about_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

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
      ChangeNotifierProvider<UpdateProvider>(
        create: (_) => UpdateProvider(),
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AboutPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Show Updates'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
    expect(find.text('Kelivo'), findsWidgets);
    expect(find.text('AGPL-3.0'), findsOneWidget);
    expect(find.text('Website'), findsNothing);
  });
}

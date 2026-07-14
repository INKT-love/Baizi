import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/custom_bottom_sheet.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';
import 'package:Kelivo/shared/widgets/qq_group_join_sheet.dart';

Widget _opener() {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showQQGroupJoinSheet(context: context),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('qq group picker uses the Baizi group on mobile', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(_opener());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(CustomBottomSheet.panelKey), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Join our QQ Group'), findsOneWidget);
      expect(find.text('Baizi QQ Group'), findsOneWidget);
      expect(find.text('Kelivo Group 1'), findsNothing);
      expect(find.text('Kelivo Group 2'), findsNothing);
      expect(
        baiziQQGroupJoinUrl,
        'mqqapi://card/show_pslcard?src_type=internal&version=1&uin=168333839&card_type=group&source=qrcode',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('qq group picker uses dialog on desktop and can be closed', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(_opener());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byKey(CustomBottomSheet.panelKey), findsNothing);
      expect(find.text('Baizi QQ Group'), findsOneWidget);
      expect(find.text('Kelivo Group 1'), findsNothing);
      expect(find.text('Kelivo Group 2'), findsNothing);

      // Close via the X button.
      await tester.tap(find.byType(IosIconButton));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

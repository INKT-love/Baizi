import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Baizi/core/providers/settings_provider.dart';
import 'package:Baizi/core/services/secure_api_key_store.dart';
import 'package:Baizi/features/settings/pages/baizi_api_key_manager_page.dart';
import 'package:Baizi/icons/lucide_adapter.dart';
import 'package:Baizi/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('shows and hides a new API key from the input suffix button', (
    tester,
  ) async {
    final settings = SettingsProvider(
      apiKeyStore: SecureApiKeyStore(backend: _MemoryBackend()),
    );
    await settings.initialization;
    await tester.pumpWidget(_testApp(settings));

    await tester.tap(find.byTooltip('Add key'));
    await tester.pumpAndSettle();

    Finder keyField() => find.byType(TextField).last;
    expect(tester.widget<TextField>(keyField()).obscureText, isTrue);
    final eye = find.byIcon(Lucide.Eye);
    expect(eye, findsOneWidget);
    expect(
      tester.getRect(eye).center.dx,
      greaterThan(tester.getRect(keyField()).center.dx),
    );

    await tester.tap(eye);
    await tester.pump();

    expect(tester.widget<TextField>(keyField()).obscureText, isFalse);
    expect(find.byIcon(Lucide.EyeOff), findsOneWidget);
  });
}

Widget _testApp(SettingsProvider settings) {
  return ChangeNotifierProvider<SettingsProvider>.value(
    value: settings,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const BaiziApiKeyManagerPage(),
    ),
  );
}

final class _MemoryBackend implements SecureApiKeyBackend {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

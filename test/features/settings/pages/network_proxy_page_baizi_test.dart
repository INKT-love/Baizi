import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/secure_api_key_store.dart';
import 'package:Kelivo/features/settings/pages/network_proxy_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('Android hides the obsolete provider proxy note', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final settings = _settings();
      addTearDown(settings.dispose);
      await settings.initialization;

      await tester.pumpWidget(_app(settings));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'When both global and provider proxies are enabled, provider-level '
          'proxy takes priority.',
        ),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop keeps the provider proxy note', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final settings = _settings();
      addTearDown(settings.dispose);
      await settings.initialization;

      await tester.pumpWidget(_app(settings));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'When both global and provider proxies are enabled, provider-level '
          'proxy takes priority.',
        ),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Widget _app(SettingsProvider settings) {
  return ChangeNotifierProvider<SettingsProvider>.value(
    value: settings,
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: NetworkProxyPage(),
    ),
  );
}

SettingsProvider _settings() {
  return SettingsProvider(
    apiKeyStore: SecureApiKeyStore(backend: _MemoryBackend()),
  );
}

final class _MemoryBackend implements SecureApiKeyBackend {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

import 'package:Baizi/core/providers/assistant_provider.dart';
import 'package:Baizi/core/providers/settings_provider.dart';
import 'package:Baizi/core/services/secure_api_key_store.dart';
import 'package:Baizi/desktop/desktop_settings_page.dart';
import 'package:Baizi/l10n/app_localizations.dart';
import 'package:Baizi/shared/widgets/ios_checkbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderConfig _providerConfig(String id) {
  return ProviderConfig(
    id: id,
    enabled: true,
    name: id,
    apiKey: 'test-key',
    baseUrl: 'https://example.test/v1',
    providerType: ProviderKind.openai,
    chatPath: '/chat/completions',
    models: const ['same-model'],
    proxyEnabled: true,
    proxyType: 'http',
    proxyHost: '127.0.0.1',
    proxyPort: '',
    proxyUsername: '',
    proxyPassword: '',
  );
}

Widget _harness(
  SettingsProvider settings, {
  required String initialProviderKey,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<AssistantProvider>(
        create: (_) => AssistantProvider(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DesktopSettingsPage(initialProviderKey: initialProviderKey),
      ),
    ),
  );
}

Future<SettingsProvider> _buildSettings() async {
  SharedPreferences.setMockInitialValues(const {});
  final settings = SettingsProvider(
    apiKeyStore: SecureApiKeyStore(backend: _MemorySecureApiKeyBackend()),
  );
  await settings.initialization;
  await settings.setProviderConfig('ProviderA', _providerConfig('ProviderA'));
  await settings.setProviderConfig('ProviderB', _providerConfig('ProviderB'));
  await settings.setProvidersOrder(const ['ProviderA', 'ProviderB']);
  return settings;
}

Future<void> _pumpProviderSettings(
  WidgetTester tester,
  SettingsProvider settings,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_harness(settings, initialProviderKey: 'ProviderA'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'desktop model selection state is cleared when provider changes',
    (tester) async {
      final settings = await _buildSettings();
      addTearDown(settings.dispose);

      await _pumpProviderSettings(tester, settings);

      await tester.tap(find.byTooltip('Multi-select').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('same-model').last);
      await tester.pump(const Duration(milliseconds: 300));

      final selectedCheckbox = tester.widget<IosCheckbox>(
        find.byType(IosCheckbox).last,
      );
      expect(selectedCheckbox.value, isTrue);

      await tester.tap(find.text('ProviderB').first);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(IosCheckbox), findsNothing);
    },
  );

  testWidgets('desktop provider proxy port input preserves typed order', (
    tester,
  ) async {
    final settings = await _buildSettings();
    addTearDown(settings.dispose);

    await _pumpProviderSettings(tester, settings);

    await tester.tap(
      find.byKey(const ValueKey('desktop-provider-settings-ProviderA')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('desktop-provider-settings-dialog')),
      findsOneWidget,
    );

    final portField = find.byKey(
      const ValueKey('desktop-provider-proxy-port-field'),
    );
    await tester.ensureVisible(portField);
    await tester.pumpAndSettle();
    await tester.tap(portField);
    await tester.pump();
    await tester.enterText(portField, '1');
    await tester.pump();

    var fieldWidget = tester.widget<TextField>(portField);
    expect(fieldWidget.controller?.selection.baseOffset, 1);

    await tester.enterText(portField, '12345');
    await tester.pump(const Duration(milliseconds: 300));

    expect(settings.getProviderConfig('ProviderA').proxyPort, '12345');

    fieldWidget = tester.widget<TextField>(portField);
    expect(fieldWidget.controller?.text, '12345');
  });

  testWidgets('desktop LobeHub icon dialog uses provider settings flow', (
    tester,
  ) async {
    final settings = await _buildSettings();
    addTearDown(settings.dispose);

    await _pumpProviderSettings(tester, settings);

    await tester.tap(
      find.byKey(const ValueKey('desktop-provider-settings-ProviderA')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('desktop-provider-settings-dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('desktop-provider-settings-avatar-ProviderA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter LobeHub Icon'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-provider-lobehub-icon-dialog')),
      findsOneWidget,
    );

    final iconField = find.byKey(
      const ValueKey('desktop-provider-lobehub-icon-field'),
    );
    await tester.enterText(iconField, 'openai');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final cfg = settings.getProviderConfig('ProviderA');
    expect(cfg.avatarType, 'lobehub');
    expect(cfg.avatarValue, 'openai');
  });
}

final class _MemorySecureApiKeyBackend implements SecureApiKeyBackend {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

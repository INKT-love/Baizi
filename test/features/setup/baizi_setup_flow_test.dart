import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/config/baizi_gateway.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/secure_api_key_store.dart';
import 'package:Kelivo/features/settings/pages/settings_page.dart';
import 'package:Kelivo/features/setup/widgets/baizi_startup_gate.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_primary_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('missing setup opens the single API Key step', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsProvider(
      apiKeyStore: SecureApiKeyStore(backend: _MemoryBackend()),
    );
    await settings.initialization;

    await tester.pumpWidget(
      _testApp(settings, const BaiziStartupGate(child: Text('HOME'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('连接白子'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('验证并获取模型'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    expect(find.textContaining('Base URL'), findsNothing);
    expect(find.text('供应商'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);

    final verifyButton = find.widgetWithText(IosPrimaryButton, '验证并获取模型');
    expect(tester.widget<IosPrimaryButton>(verifyButton).onTap, isNull);

    await tester.enterText(find.byType(TextField), 'test-key');
    await tester.pump();

    expect(tester.widget<IosPrimaryButton>(verifyButton).onTap, isNotNull);
  });

  testWidgets('cached models require an explicit choice before chat', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'baizi_models_cache_v1': <String>['gpt-5', 'claude-sonnet-4-6'],
    });
    final backend = _MemoryBackend()
      ..values[SecureApiKeyStore.storageKey] = 'secure-key';
    final settings = SettingsProvider(
      apiKeyStore: SecureApiKeyStore(backend: backend),
    );
    await settings.initialization;

    await tester.pumpWidget(
      _testApp(settings, const BaiziStartupGate(child: Text('HOME'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('选择模型'), findsOneWidget);
    expect(find.text('gpt-5'), findsOneWidget);
    expect(find.text('claude-sonnet-4-6'), findsOneWidget);

    await tester.tap(find.text('gpt-5'));
    await tester.pumpAndSettle();

    expect(settings.currentModelProvider, BaiziGateway.providerId);
    expect(settings.currentModelId, 'gpt-5');
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('settings keeps provider concepts out of the basic page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'baizi_models_cache_v1': <String>['gpt-5'],
      'selected_model_v1': '${BaiziGateway.providerId}::gpt-5',
    });
    final backend = _MemoryBackend()
      ..values[SecureApiKeyStore.storageKey] = 'secure-key';
    final settings = SettingsProvider(
      apiKeyStore: SecureApiKeyStore(backend: backend),
    );
    await settings.initialization;

    await tester.pumpWidget(_testApp(settings, const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('当前模型'), findsOneWidget);
    expect(find.text('高级功能'), findsWidgets);
    expect(find.text('供应商'), findsNothing);
    expect(find.text('搜索服务'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pumpAndSettle();
    await tester.tap(find.text('高级功能').last);
    await tester.pumpAndSettle();

    expect(find.text('搜索服务'), findsOneWidget);
    expect(find.text('供应商'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });
}

Widget _testApp(SettingsProvider settings, Widget home) {
  return ChangeNotifierProvider<SettingsProvider>.value(
    value: settings,
    child: MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: home,
    ),
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

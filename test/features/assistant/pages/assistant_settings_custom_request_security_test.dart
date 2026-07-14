import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/memory_provider.dart';
import 'package:Kelivo/core/providers/quick_phrase_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/secure_api_key_store.dart';
import 'package:Kelivo/features/assistant/pages/assistant_settings_edit_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

const _assistantId = 'assistant-custom-request-security';

Future<AssistantProvider> _createAssistantProvider(WidgetTester tester) async {
  final provider = AssistantProvider();
  for (var i = 0; i < 25; i++) {
    if (provider.getById(_assistantId) != null) return provider;
    await tester.pump(const Duration(milliseconds: 10));
  }
  return provider;
}

Widget _buildHarness(AssistantProvider assistantProvider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(
          apiKeyStore: SecureApiKeyStore(backend: _MemorySecureApiKeyBackend()),
        ),
      ),
      ChangeNotifierProvider<AssistantProvider>.value(value: assistantProvider),
      ChangeNotifierProvider<MemoryProvider>(create: (_) => MemoryProvider()),
      ChangeNotifierProvider<QuickPhraseProvider>(
        create: (_) => QuickPhraseProvider(),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AssistantSettingsEditPage(assistantId: _assistantId),
    ),
  );
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

Future<void> _openCustomRequestTab(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Custom').first);
  await tester.tap(find.text('Custom').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Custom Headers'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'assistants_v1': Assistant.encodeList(const <Assistant>[
        Assistant(id: _assistantId, name: 'Test Assistant'),
      ]),
      'mobile_assistant_detail_outline_enabled_v1': true,
    });
  });

  testWidgets('protected header drafts never reach assistant persistence', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final assistantProvider = await _createAssistantProvider(tester);

    await tester.pumpWidget(_buildHarness(assistantProvider));
    await tester.pump(const Duration(milliseconds: 300));
    await _openCustomRequestTab(tester);
    await tester.tap(find.text('Add Header'));
    await tester.pump();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'Bearer unsafe');
    await tester.enterText(fields.at(0), 'Authorization');
    await tester.pump();

    expect(
      assistantProvider.getById(_assistantId)!.customHeaders,
      isEmpty,
      reason: 'draft values must not be persisted while they are edited',
    );

    await tester.tap(find.text('Custom Body'));
    await tester.pumpAndSettle();
    expect(assistantProvider.getById(_assistantId)!.customHeaders, isEmpty);

    await tester.tap(find.text('Add Body'));
    await tester.pump();
    final bodyFields = find.byType(TextField);
    await tester.enterText(bodyFields.at(3), 'sk-unsafe');
    await tester.enterText(bodyFields.at(2), 'apiKey');
    await tester.pump();
    expect(
      find.text('Managed by Baizi and cannot be customized'),
      findsNWidgets(2),
    );
    expect(assistantProvider.getById(_assistantId)!.customBody, isEmpty);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(assistantProvider.getById(_assistantId)!.customBody, isEmpty);
  });

  testWidgets('safe advanced header and body fields persist on commit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final assistantProvider = await _createAssistantProvider(tester);

    await tester.pumpWidget(_buildHarness(assistantProvider));
    await tester.pump(const Duration(milliseconds: 300));
    await _openCustomRequestTab(tester);
    await tester.tap(find.text('Add Header'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'X-Trace-Id');
    await tester.enterText(find.byType(TextField).at(1), 'trace-1');
    await tester.tap(find.text('Custom Body'));
    await tester.pumpAndSettle();

    expect(assistantProvider.getById(_assistantId)!.customHeaders, <dynamic>[
      <String, String>{'name': 'X-Trace-Id', 'value': 'trace-1'},
    ]);

    await tester.tap(find.text('Add Body'));
    await tester.pump();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(2), 'max_tokens');
    await tester.enterText(fields.at(3), '4096');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(assistantProvider.getById(_assistantId)!.customBody, <dynamic>[
      <String, String>{'key': 'max_tokens', 'value': '4096'},
    ]);
  });
}

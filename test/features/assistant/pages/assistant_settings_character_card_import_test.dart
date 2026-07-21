import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Baizi/core/models/assistant.dart';
import 'package:Baizi/core/models/character_card.dart';
import 'package:Baizi/core/providers/assistant_provider.dart';
import 'package:Baizi/core/providers/settings_provider.dart';
import 'package:Baizi/core/providers/world_book_provider.dart';
import 'package:Baizi/core/services/character_card/character_card_import_service.dart';
import 'package:Baizi/core/services/secure_api_key_store.dart';
import 'package:Baizi/core/services/world_book_store.dart';
import 'package:Baizi/features/assistant/pages/assistant_settings_page.dart';
import 'package:Baizi/l10n/app_localizations.dart';
import 'package:Baizi/shared/widgets/snackbar.dart';

class _FilePicker extends FilePicker {
  _FilePicker(this.path);

  final String path;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    @Deprecated('No effect in this test.') bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return FilePickerResult(<PlatformFile>[
      PlatformFile(
        name: path.replaceAll('\\', '/').split('/').last,
        size: 1,
        path: path,
      ),
    ]);
  }
}

class _CharacterCardImportService extends CharacterCardImportService {
  _CharacterCardImportService({required this.preview, this.prepareError});

  final CharacterCardImportPreview preview;
  final Object? prepareError;
  String? lastOverwriteAssistantId;
  int commitCount = 0;

  @override
  Future<CharacterCardImportPreview> prepareFile(String filePath) async {
    if (prepareError != null) throw prepareError!;
    return preview;
  }

  @override
  Future<CharacterCardImportResult> commit({
    required CharacterCardImportPreview preview,
    required AssistantProvider assistantProvider,
    WorldBookProvider? worldBookProvider,
    String? overwriteAssistantId,
    required String copySuffix,
  }) async {
    commitCount++;
    lastOverwriteAssistantId = overwriteAssistantId;
    return CharacterCardImportResult(
      assistantId: overwriteAssistantId ?? 'luna-copy',
      assistantName: overwriteAssistantId == null ? 'Luna 副本' : 'Luna',
      overwritten: overwriteAssistantId != null,
    );
  }
}

class _MemorySecureStorage implements SecureApiKeyBackend {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

CharacterCardImportPreview _preview({bool includeWorldBook = true}) {
  return CharacterCardImportPreview(
    sourceFileName: 'luna.json',
    isPng: false,
    sourceBytes: Uint8List.fromList(const <int>[123, 125]),
    document: CharacterCardDocument(
      spec: CharacterCardSpec.v3,
      specVersion: '3.0',
      data: CharacterCardData(
        name: 'Luna',
        description: '月光下的向导',
        personality: '冷静',
        scenario: '天文台',
        firstMes: '晚上好，{{user}}。',
        alternateGreetings: const <String>['欢迎回来。'],
        characterBook: includeWorldBook
            ? CharacterBookData(
                name: '月光设定',
                entries: <CharacterBookEntryData>[
                  CharacterBookEntryData(
                    keys: const <String>['月亮'],
                    content: '天文台只在夜间开放。',
                  ),
                ],
              )
            : null,
      ),
    ),
  );
}

Future<AssistantProvider> _provider(
  WidgetTester tester, {
  String modelId = 'kept-model',
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'assistants_v1': Assistant.encodeList(<Assistant>[
      Assistant(
        id: 'luna-existing',
        name: 'Luna',
        chatModelProvider: 'baizi',
        chatModelId: modelId,
        enableMemory: true,
      ),
    ]),
    'current_assistant_id_v1': 'luna-existing',
  });
  await WorldBookStore.clear();
  final provider = AssistantProvider();
  for (var attempt = 0; attempt < 50; attempt++) {
    if (provider.assistants.length == 1) return provider;
    await tester.pump(const Duration(milliseconds: 10));
  }
  return provider;
}

Widget _harness({
  required AssistantProvider assistantProvider,
  required WorldBookProvider worldBookProvider,
  required CharacterCardImportService service,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(
          apiKeyStore: SecureApiKeyStore(backend: _MemorySecureStorage()),
        ),
      ),
      ChangeNotifierProvider<AssistantProvider>.value(value: assistantProvider),
      ChangeNotifierProvider<WorldBookProvider>.value(value: worldBookProvider),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: AssistantSettingsPage(characterCardImportService: service),
    ),
  );
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('previews a same-name card and defaults to creating a copy', (
    tester,
  ) async {
    FilePicker.platform = _FilePicker('luna.json');
    final assistantProvider = await _provider(tester);
    final worldBookProvider = WorldBookProvider();
    await worldBookProvider.initialize();
    final service = _CharacterCardImportService(preview: _preview());
    await tester.pumpWidget(
      _harness(
        assistantProvider: assistantProvider,
        worldBookProvider: worldBookProvider,
        service: service,
      ),
    );
    await _pumpUi(tester);

    await tester.tap(
      find.byKey(const ValueKey('assistant-import-character-card')),
    );
    await _pumpUi(tester);

    expect(
      find.byKey(const ValueKey('character-card-import-preview')),
      findsOneWidget,
    );
    expect(find.text('预览角色卡'), findsOneWidget);
    expect(find.text('月光下的向导'), findsOneWidget);
    expect(find.text('开场白：2 条'), findsOneWidget);
    expect(find.text('世界书条目：1 条'), findsOneWidget);
    expect(find.text('创建副本'), findsOneWidget);
    expect(find.text('覆盖角色'), findsOneWidget);

    final confirm = find.byKey(const ValueKey('character-card-import-confirm'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await _pumpUi(tester);

    expect(service.commitCount, 1);
    expect(service.lastOverwriteAssistantId, isNull);
    expect(
      AppSnackBarManager().activeToasts.first.notification.message,
      '已导入 Luna 副本',
    );
    await _drainToast(tester);
  });

  testWidgets('explicit overwrite keeps the assistant id and settings', (
    tester,
  ) async {
    FilePicker.platform = _FilePicker('luna.json');
    final assistantProvider = await _provider(tester);
    final worldBookProvider = WorldBookProvider();
    await worldBookProvider.initialize();
    final service = _CharacterCardImportService(
      preview: _preview(includeWorldBook: false),
    );
    await tester.pumpWidget(
      _harness(
        assistantProvider: assistantProvider,
        worldBookProvider: worldBookProvider,
        service: service,
      ),
    );
    await _pumpUi(tester);

    await tester.tap(
      find.byKey(const ValueKey('assistant-import-character-card')),
    );
    await _pumpUi(tester);
    await tester.tap(find.text('覆盖角色'));
    await _pumpUi(tester);
    final confirm = find.byKey(const ValueKey('character-card-import-confirm'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await _pumpUi(tester);

    expect(service.commitCount, 1);
    expect(service.lastOverwriteAssistantId, 'luna-existing');
    expect(
      assistantProvider.getById('luna-existing')?.chatModelId,
      'kept-model',
    );
    await _drainToast(tester);
  });

  testWidgets('invalid card reports a localized recoverable error', (
    tester,
  ) async {
    FilePicker.platform = _FilePicker('broken.json');
    final assistantProvider = await _provider(tester);
    final worldBookProvider = WorldBookProvider();
    final service = _CharacterCardImportService(
      preview: _preview(),
      prepareError: const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidJson,
        'Invalid JSON.',
      ),
    );
    await tester.pumpWidget(
      _harness(
        assistantProvider: assistantProvider,
        worldBookProvider: worldBookProvider,
        service: service,
      ),
    );
    await _pumpUi(tester);

    await tester.tap(
      find.byKey(const ValueKey('assistant-import-character-card')),
    );
    await _pumpUi(tester);

    expect(
      AppSnackBarManager().activeToasts.first.notification.message,
      '角色卡内容不完整或包含无效数据。',
    );
    expect(
      find.byKey(const ValueKey('character-card-import-preview')),
      findsNothing,
    );
    expect(assistantProvider.assistants, hasLength(1));
    await _drainToast(tester);
  });
}

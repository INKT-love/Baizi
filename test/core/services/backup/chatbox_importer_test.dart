import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/models/backup.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/backup/chatbox_importer.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';

  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kelivo_chatbox_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    SharedPreferences.setMockInitialValues({
      'provider_configs_v1': '{"baizi":{"id":"baizi","baseUrl":"fixed-local"}}',
      'providers_order_v1': <String>['baizi'],
    });
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'imports assistants without importing provider credentials or endpoints',
    () async {
      final backup = File('${tempDir.path}/chatbox.json');
      await backup.writeAsString(
        jsonEncode(<String, dynamic>{
          '__exported_at': '2026-01-01T00:00:00.000Z',
          'settings': <String, dynamic>{
            'providers': <String, dynamic>{
              'openai': <String, dynamic>{
                'apiKey': 'sk-imported',
                'apiHost': 'https://imported.example',
                'apiPath': '/v1/chat/completions',
                'models': <Map<String, dynamic>>[
                  <String, dynamic>{'modelId': 'gpt-chatbox'},
                ],
              },
            },
          },
          'chat-sessions-list': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'assistant-1', 'name': 'Chatbox Assistant'},
          ],
          'session:assistant-1': <String, dynamic>{
            'settings': <String, dynamic>{
              'provider': 'openai',
              'modelId': 'gpt-chatbox',
            },
            'threads': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'thread-1',
                'name': 'Imported Thread',
                'messages': <dynamic>[],
              },
            ],
            'messages': <dynamic>[],
          },
        }),
      );

      final result = await ChatboxImporter.importFromChatbox(
        file: backup,
        mode: RestoreMode.overwrite,
        settings: SettingsProvider(),
        chatService: ChatService(),
      );

      expect(result.providers, 0);
      expect(result.assistants, 1);
      expect(result.conversations, 1);

      final prefs = await SharedPreferences.getInstance();
      final providerConfigs = prefs.getString('provider_configs_v1') ?? '';
      expect(providerConfigs, isNot(contains('sk-imported')));
      expect(providerConfigs, isNot(contains('imported.example')));
      expect(
        prefs.getStringList('providers_order_v1'),
        isNot(contains('openai')),
      );

      final assistants =
          jsonDecode(prefs.getString('assistants_v1')!) as List<dynamic>;
      final assistant = assistants.single as Map<String, dynamic>;
      expect(assistant['chatModelProvider'], 'baizi');
      expect(assistant['chatModelId'], 'gpt-chatbox');
    },
  );
}

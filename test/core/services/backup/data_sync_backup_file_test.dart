import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/models/backup.dart';
import 'package:Kelivo/core/services/backup/data_sync.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/utils/app_directories.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

void main() {
  group('DataSync backup file', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kelivo_data_sync_test_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(root.path);
      SharedPreferences.setMockInitialValues({'backup_test_key': 'value'});
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test(
      'packs files as deflated zip entries and removes staging files',
      () async {
        final uploadDir = Directory('${root.path}/upload');
        await uploadDir.create(recursive: true);
        final uploadFile = File('${uploadDir.path}/large.bin');
        await uploadFile.writeAsBytes(List<int>.filled(1024 * 1024, 7));
        final fontsDir = Directory('${root.path}/fonts');
        await fontsDir.create(recursive: true);
        final fontFile = File('${fontsDir.path}/custom.ttf');
        await fontFile.writeAsBytes(List<int>.filled(256, 9));
        final characterCardsDir = Directory('${root.path}/character_cards');
        await characterCardsDir.create(recursive: true);
        final characterCardFile = File(
          '${characterCardsDir.path}/nested/archivist.json',
        );
        await characterCardFile.parent.create(recursive: true);
        await characterCardFile.writeAsString('{"name":"Archivist"}');

        final tmpDir = Directory('${root.path}/tmp');
        final staleWorkDir = Directory('${tmpDir.path}/kelivo_backup_stale');
        await staleWorkDir.create(recursive: true);
        await File('${staleWorkDir.path}/orphan.zip').writeAsString('old');
        await File('${tmpDir.path}/kelivo_backup_old.zip').writeAsString('old');
        await File('${tmpDir.path}/_bk_chats.json').writeAsString('{}');

        final sync = DataSync(chatService: ChatService());
        final backupFile = await sync.prepareBackupFile(
          const WebDavConfig(includeChats: false, includeFiles: true),
        );

        expect(await staleWorkDir.exists(), isFalse);
        expect(
          await File('${tmpDir.path}/kelivo_backup_old.zip').exists(),
          isFalse,
        );
        expect(await File('${tmpDir.path}/_bk_chats.json').exists(), isFalse);

        final input = InputFileStream(backupFile.path);
        Archive? archive;
        try {
          archive = ZipDecoder().decodeStream(input);
          final settingsEntry = archive.findFile('settings.json');
          final uploadEntry = archive.findFile('upload/large.bin');
          final fontEntry = archive.findFile('fonts/custom.ttf');
          final characterCardEntry = archive.findFile(
            'character_cards/nested/archivist.json',
          );

          expect(settingsEntry, isNotNull);
          expect(uploadEntry, isNotNull);
          expect(fontEntry, isNotNull);
          expect(characterCardEntry, isNotNull);
          expect(settingsEntry!.compression, CompressionType.deflate);
          expect(uploadEntry!.compression, CompressionType.deflate);
          expect(fontEntry!.compression, CompressionType.deflate);
          expect(characterCardEntry!.compression, CompressionType.deflate);
          expect(uploadEntry.readBytes(), List<int>.filled(1024 * 1024, 7));
          expect(fontEntry.readBytes(), List<int>.filled(256, 9));
          expect(
            utf8.decode(characterCardEntry.readBytes()!),
            '{"name":"Archivist"}',
          );
        } finally {
          archive?.clearSync();
          input.closeSync();
        }

        expect(
          await File('${backupFile.parent.path}/_bk_settings.json').exists(),
          isFalse,
        );

        await DataSync.cleanupTemporaryBackupFile(backupFile);

        expect(await backupFile.exists(), isFalse);
        expect(await backupFile.parent.exists(), isFalse);
      },
    );

    test('uses a dedicated managed character card directory', () async {
      final directory = await AppDirectories.getCharacterCardsDirectory();

      expect(directory.path, Directory('${root.path}/character_cards').path);
    });

    test('backup settings omit provider and credential preferences', () async {
      SharedPreferences.setMockInitialValues({
        'provider_configs_v1': '{"openai":{"apiKey":"sk-export"}}',
        'provider_configs_backup_v1': '{"claude":{}}',
        'providers_order_v1': ['openai', 'claude'],
        'provider_groups_v1': '[]',
        'provider_group_map_v1': '{}',
        'provider_group_collapsed_v1': '{}',
        'provider_ungrouped_position_v1': 1,
        'provider_credentials_v1': 'credential',
        'legacy_api_key_v1': 'sk-legacy',
        'theme_mode_v1': 'dark',
      });

      final sync = DataSync(chatService: ChatService());
      final backupFile = await sync.prepareBackupFile(
        const WebDavConfig(includeChats: false, includeFiles: false),
      );

      final input = InputFileStream(backupFile.path);
      Archive? archive;
      try {
        archive = ZipDecoder().decodeStream(input);
        final settingsEntry = archive.findFile('settings.json');
        expect(settingsEntry, isNotNull);
        final settings =
            jsonDecode(utf8.decode(settingsEntry!.readBytes()!))
                as Map<String, dynamic>;

        for (final key in <String>[
          'provider_configs_v1',
          'provider_configs_backup_v1',
          'providers_order_v1',
          'provider_groups_v1',
          'provider_group_map_v1',
          'provider_group_collapsed_v1',
          'provider_ungrouped_position_v1',
          'provider_credentials_v1',
          'legacy_api_key_v1',
        ]) {
          expect(settings, isNot(contains(key)), reason: key);
        }
        expect(settings['theme_mode_v1'], 'dark');
      } finally {
        archive?.clearSync();
        input.closeSync();
        await DataSync.cleanupTemporaryBackupFile(backupFile);
      }
    });

    test(
      'overwrite and merge restore keep provider data local and normalize assistants',
      () async {
        final settingsFile = File('${root.path}/legacy_settings.json');
        await settingsFile.writeAsString(
          jsonEncode({
            'provider_configs_v1': jsonEncode({
              'openai': {
                'apiKey': 'sk-imported',
                'baseUrl': 'https://imported.example/v1',
              },
            }),
            'provider_configs_backup_v1': jsonEncode({'claude': {}}),
            'providers_order_v1': ['openai'],
            'provider_groups_v1': '[]',
            'provider_group_map_v1': '{}',
            'provider_group_collapsed_v1': '{}',
            'provider_ungrouped_position_v1': 2,
            'provider_credentials_v1': 'imported-credential',
            'legacy_api_key_v1': 'sk-imported-legacy',
            'assistants_v1': jsonEncode([
              {
                'id': 'legacy-assistant',
                'name': 'Legacy Assistant',
                'chatModelProvider': 'openai',
                'chatModelId': 'gpt-4.1',
              },
            ]),
            'theme_mode_v1': 'dark',
          }),
        );

        final zipFile = File('${root.path}/legacy_settings.zip');
        final encoder = ZipFileEncoder();
        encoder.create(zipFile.path);
        encoder.addFileSync(settingsFile, 'settings.json');
        encoder.closeSync();

        for (final mode in <RestoreMode>[
          RestoreMode.overwrite,
          RestoreMode.merge,
        ]) {
          final localProviderConfig = jsonEncode({
            'baizi': {'id': 'baizi', 'baseUrl': 'fixed-local'},
          });
          SharedPreferences.setMockInitialValues({
            'provider_configs_v1': localProviderConfig,
            'provider_configs_backup_v1': '{"baizi":{}}',
            'providers_order_v1': ['baizi'],
            'provider_groups_v1': '[{"id":"local"}]',
            'provider_group_map_v1': '{"baizi":"local"}',
            'provider_group_collapsed_v1': '{"local":false}',
            'provider_ungrouped_position_v1': 7,
          });

          final sync = DataSync(chatService: ChatService());
          await sync.restoreFromLocalFile(
            zipFile,
            const WebDavConfig(includeChats: false, includeFiles: false),
            mode: mode,
          );

          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('provider_configs_v1'), localProviderConfig);
          expect(prefs.getString('provider_configs_backup_v1'), '{"baizi":{}}');
          expect(prefs.getStringList('providers_order_v1'), ['baizi']);
          expect(prefs.getString('provider_groups_v1'), '[{"id":"local"}]');
          expect(prefs.getString('provider_group_map_v1'), '{"baizi":"local"}');
          expect(
            prefs.getString('provider_group_collapsed_v1'),
            '{"local":false}',
          );
          expect(prefs.getInt('provider_ungrouped_position_v1'), 7);
          expect(prefs.getString('provider_credentials_v1'), isNull);
          expect(prefs.getString('legacy_api_key_v1'), isNull);

          final assistants =
              jsonDecode(prefs.getString('assistants_v1')!) as List<dynamic>;
          final assistant = assistants.single as Map<String, dynamic>;
          expect(assistant['chatModelProvider'], 'baizi');
          expect(assistant['chatModelId'], 'gpt-4.1');
          expect(prefs.getString('theme_mode_v1'), 'dark');
        }
      },
    );

    test('restores managed font files in overwrite and merge modes', () async {
      final sourceDir = Directory('${root.path}/source_fonts');
      await sourceDir.create(recursive: true);
      final sourceFile = File('${sourceDir.path}/custom.ttf');
      await sourceFile.writeAsBytes(List<int>.filled(128, 5));

      final zipFile = File('${root.path}/fonts_backup.zip');
      final encoder = ZipFileEncoder();
      encoder.create(zipFile.path);
      encoder.addFileSync(sourceFile, 'fonts/custom.ttf');
      encoder.closeSync();

      final fontsDir = Directory('${root.path}/fonts');
      await fontsDir.create(recursive: true);
      final existingFile = File('${fontsDir.path}/existing.ttf');
      await existingFile.writeAsBytes(List<int>.filled(64, 3));

      final sync = DataSync(chatService: ChatService());
      await sync.restoreFromLocalFile(
        zipFile,
        const WebDavConfig(includeChats: false, includeFiles: true),
        mode: RestoreMode.merge,
      );

      expect(await existingFile.exists(), isTrue);
      expect(
        await File('${fontsDir.path}/custom.ttf').readAsBytes(),
        List<int>.filled(128, 5),
      );

      await sync.restoreFromLocalFile(
        zipFile,
        const WebDavConfig(includeChats: false, includeFiles: true),
        mode: RestoreMode.overwrite,
      );

      expect(await existingFile.exists(), isFalse);
      expect(
        await File('${fontsDir.path}/custom.ttf').readAsBytes(),
        List<int>.filled(128, 5),
      );
    });

    test(
      'restores character cards with local-first merge and full overwrite',
      () async {
        final sourceDir = Directory('${root.path}/source_character_cards');
        await sourceDir.create(recursive: true);
        final incomingFile = File('${sourceDir.path}/incoming/card.json');
        await incomingFile.parent.create(recursive: true);
        await incomingFile.writeAsString('incoming-only');
        final conflictingFile = File('${sourceDir.path}/shared.json');
        await conflictingFile.writeAsString('incoming-shared');

        final zipFile = File('${root.path}/character_cards_backup.zip');
        final encoder = ZipFileEncoder();
        encoder.create(zipFile.path);
        encoder.addFileSync(incomingFile, 'character_cards/incoming/card.json');
        encoder.addFileSync(conflictingFile, 'character_cards/shared.json');
        encoder.closeSync();

        final destination = Directory('${root.path}/character_cards');
        await destination.create(recursive: true);
        final localOnlyFile = File('${destination.path}/local-only.json');
        await localOnlyFile.writeAsString('local-only');
        final localSharedFile = File('${destination.path}/shared.json');
        await localSharedFile.writeAsString('local-shared');

        final sync = DataSync(chatService: ChatService());
        await sync.restoreFromLocalFile(
          zipFile,
          const WebDavConfig(includeChats: false, includeFiles: true),
          mode: RestoreMode.merge,
        );

        expect(await localOnlyFile.readAsString(), 'local-only');
        expect(await localSharedFile.readAsString(), 'local-shared');
        expect(
          await File('${destination.path}/incoming/card.json').readAsString(),
          'incoming-only',
        );

        await sync.restoreFromLocalFile(
          zipFile,
          const WebDavConfig(includeChats: false, includeFiles: true),
          mode: RestoreMode.overwrite,
        );

        expect(await localOnlyFile.exists(), isFalse);
        expect(await localSharedFile.readAsString(), 'incoming-shared');
        expect(
          await File('${destination.path}/incoming/card.json').readAsString(),
          'incoming-only',
        );
      },
    );

    test(
      'merge restore imports memories and safely merges MCP credentials',
      () async {
        SharedPreferences.setMockInitialValues({
          'assistant_memories_v1': jsonEncode([
            {'id': 1, 'assistantId': 'local', 'content': 'keep local'},
            {'id': 2, 'assistantId': 'dup', 'content': 'same memory'},
          ]),
          'mcp_servers_v1': jsonEncode([
            {
              'id': 'local-server',
              'enabled': true,
              'name': 'Local Server',
              'transport': 'sse',
              'url': 'http://local.example/sse',
              'tools': [],
            },
            {
              'id': 'shared-server',
              'enabled': true,
              'name': 'Local Shared Server',
              'transport': 'sse',
              'url': 'http://shared.example/sse',
              'tools': [],
              'headers': {
                'Authorization': 'Bearer local-mcp-secret',
                'X-Trace-Id': 'local-trace',
              },
            },
            {
              'id': 'moved-server',
              'enabled': true,
              'name': 'Local Moved Server',
              'transport': 'sse',
              'url': 'http://old-target.example/sse',
              'tools': [],
              'headers': {'Authorization': 'Bearer must-not-forward-mcp'},
            },
          ]),
        });

        final settingsFile = File('${root.path}/settings.json');
        await settingsFile.writeAsString(
          jsonEncode({
            'assistant_memories_v1': jsonEncode([
              {'id': 1, 'assistantId': 'remote', 'content': 'remote memory'},
              {'id': 2, 'assistantId': 'dup', 'content': 'same memory'},
              {'id': 4, 'assistantId': 'new', 'content': 'new memory'},
            ]),
            'mcp_servers_v1': jsonEncode([
              {
                'id': 'shared-server',
                'enabled': false,
                'name': 'Imported Shared Server',
                'transport': 'sse',
                'url': 'http://shared.example/sse',
                'tools': [],
                'headers': {
                  'Authorization': '',
                  'X-Trace-Id': 'imported-trace',
                },
              },
              {
                'id': 'moved-server',
                'enabled': true,
                'name': 'Imported Moved Server',
                'transport': 'sse',
                'url': 'http://new-target.example/sse',
                'tools': [],
              },
              {
                'id': 'remote-server',
                'enabled': true,
                'name': 'Remote Server',
                'transport': 'http',
                'url': 'http://remote.example/mcp',
                'tools': [],
                'headers': {'Authorization': '<redacted>'},
              },
            ]),
          }),
        );

        final zipFile = File('${root.path}/settings_merge_backup.zip');
        final encoder = ZipFileEncoder();
        encoder.create(zipFile.path);
        encoder.addFileSync(settingsFile, 'settings.json');
        encoder.closeSync();

        final sync = DataSync(chatService: ChatService());
        await sync.restoreFromLocalFile(
          zipFile,
          const WebDavConfig(includeChats: false, includeFiles: false),
          mode: RestoreMode.merge,
        );

        final prefs = await SharedPreferences.getInstance();
        final memories =
            jsonDecode(prefs.getString('assistant_memories_v1')!) as List;
        expect(memories, hasLength(4));
        expect(
          memories.where(
            (e) =>
                (e as Map)['assistantId'] == 'dup' &&
                e['content'] == 'same memory',
          ),
          hasLength(1),
        );
        expect(
          memories.any(
            (e) =>
                (e as Map)['assistantId'] == 'remote' &&
                e['content'] == 'remote memory' &&
                e['id'] != 1,
          ),
          isTrue,
        );
        expect(
          memories.any(
            (e) =>
                (e as Map)['assistantId'] == 'new' &&
                e['content'] == 'new memory' &&
                e['id'] == 4,
          ),
          isTrue,
        );

        final servers = jsonDecode(prefs.getString('mcp_servers_v1')!) as List;
        expect(servers, hasLength(4));
        final shared =
            servers.where((e) => (e as Map)['id'] == 'shared-server').single
                as Map;
        expect(shared['name'], 'Imported Shared Server');
        expect(shared['enabled'], isFalse);
        expect(
          (shared['headers'] as Map)['Authorization'],
          'Bearer local-mcp-secret',
        );
        expect((shared['headers'] as Map)['X-Trace-Id'], 'imported-trace');
        final moved =
            servers.where((e) => (e as Map)['id'] == 'moved-server').single
                as Map;
        expect(moved['url'], 'http://new-target.example/sse');
        expect(
          moved['headers'] as Map? ?? const <String, Object?>{},
          isNot(contains('Authorization')),
        );
        expect(
          servers.any(
            (e) =>
                (e as Map)['id'] == 'remote-server' &&
                e['name'] == 'Remote Server',
          ),
          isTrue,
        );
        final remote =
            servers.where((e) => (e as Map)['id'] == 'remote-server').single
                as Map;
        expect(
          remote['headers'] as Map? ?? const <String, Object?>{},
          isNot(contains('Authorization')),
        );
      },
    );

    test(
      'merge restore safely merges search TTS and backup-store credentials',
      () async {
        SharedPreferences.setMockInitialValues({
          'search_services_v1': jsonEncode([
            {
              'id': 'search-local',
              'type': 'tavily',
              'url': 'https://local-search.example',
              'apiKey': 'local-only-search-secret',
            },
            {
              'id': 'search-shared',
              'type': 'tavily',
              'url': 'https://shared-search.example',
              'apiKey': 'local-search-secret',
              'label': 'Local search',
            },
          ]),
          'tts_services_v1': jsonEncode([
            {
              'id': 'tts-local',
              'kind': 'openai',
              'baseUrl': 'https://local-tts.example/v1',
              'apiKey': 'local-only-tts-secret',
              'voice': 'alloy',
            },
            {
              'id': 'tts-shared',
              'kind': 'openai',
              'baseUrl': 'https://shared-tts.example/v1',
              'apiKey': 'local-tts-secret',
              'voice': 'alloy',
            },
          ]),
          'webdav_config_v1': jsonEncode({
            'url': 'https://dav.example',
            'username': 'local-user',
            'password': 'local-dav-secret',
            'path': 'local-backups',
          }),
          's3_config_v1': jsonEncode({
            'endpoint': 'https://s3.example',
            'bucket': 'local-bucket',
            'accessKeyId': 'local-access-key',
            'secretAccessKey': 'local-s3-secret',
          }),
        });

        final settingsFile = File('${root.path}/credential_settings.json');
        await settingsFile.writeAsString(
          jsonEncode({
            'search_services_v1': jsonEncode([
              {
                'id': 'search-shared',
                'type': 'tavily',
                'url': 'https://shared-search.example',
                'apiKey': '',
                'label': 'Imported search',
              },
              {
                'id': 'search-new',
                'type': 'exa',
                'url': 'https://new-search.example',
                'apiKey': '<redacted>',
              },
            ]),
            'tts_services_v1': jsonEncode([
              {
                'id': 'tts-shared',
                'kind': 'openai',
                'baseUrl': 'https://shared-tts.example/v1',
                'apiKey': '',
                'voice': 'nova',
              },
              {
                'id': 'tts-new',
                'kind': 'gemini',
                'baseUrl': 'https://new-tts.example',
                'apiKey': '<redacted>',
              },
            ]),
            'webdav_config_v1': jsonEncode({
              'url': 'https://dav.example',
              'username': 'imported-user',
              'password': '',
              'path': 'imported-backups',
            }),
            's3_config_v1': jsonEncode({
              'endpoint': 'https://s3.example',
              'bucket': 'imported-bucket',
              'accessKeyId': '',
              'secretAccessKey': '<redacted>',
            }),
          }),
        );

        final zipFile = File('${root.path}/credential_settings_backup.zip');
        final encoder = ZipFileEncoder();
        encoder.create(zipFile.path);
        encoder.addFileSync(settingsFile, 'settings.json');
        encoder.closeSync();

        final sync = DataSync(chatService: ChatService());
        await sync.restoreFromLocalFile(
          zipFile,
          const WebDavConfig(includeChats: false, includeFiles: false),
          mode: RestoreMode.merge,
        );

        final prefs = await SharedPreferences.getInstance();
        Map<String, Map<String, dynamic>> listById(String key) {
          final list = jsonDecode(prefs.getString(key)!) as List<dynamic>;
          return <String, Map<String, dynamic>>{
            for (final item in list.cast<Map>())
              item['id'] as String: item.cast<String, dynamic>(),
          };
        }

        final search = listById('search_services_v1');
        expect(
          search.keys,
          containsAll(<String>['search-local', 'search-shared', 'search-new']),
        );
        expect(search['search-local']!['apiKey'], 'local-only-search-secret');
        expect(search['search-shared']!['apiKey'], 'local-search-secret');
        expect(search['search-shared']!['label'], 'Imported search');
        expect(search['search-new']!['apiKey'], '');

        final tts = listById('tts_services_v1');
        expect(
          tts.keys,
          containsAll(<String>['tts-local', 'tts-shared', 'tts-new']),
        );
        expect(tts['tts-local']!['apiKey'], 'local-only-tts-secret');
        expect(tts['tts-shared']!['apiKey'], 'local-tts-secret');
        expect(tts['tts-shared']!['voice'], 'nova');
        expect(tts['tts-new'], isNot(contains('apiKey')));

        final webDav = jsonDecode(prefs.getString('webdav_config_v1')!) as Map;
        expect(webDav['password'], 'local-dav-secret');
        expect(webDav['username'], 'imported-user');
        expect(webDav['path'], 'imported-backups');

        final s3 = jsonDecode(prefs.getString('s3_config_v1')!) as Map;
        expect(s3['accessKeyId'], 'local-access-key');
        expect(s3['secretAccessKey'], 'local-s3-secret');
        expect(s3['bucket'], 'imported-bucket');
      },
    );

    test(
      'merge restore preserves and deduplicates world book settings',
      () async {
        SharedPreferences.setMockInitialValues({
          'world_books_v1': jsonEncode([
            {'id': 'local-book', 'name': 'Local'},
            {'id': 'shared-book', 'name': 'Local Shared'},
            {'id': 'shared-book', 'name': 'Local Duplicate'},
          ]),
          'world_books_active_ids_by_assistant_v1': jsonEncode({
            'assistant-a': ['local-book', 'shared-book', 'shared-book'],
          }),
          'world_books_collapsed_v1': jsonEncode({
            'local-book': true,
            'shared-book': false,
          }),
        });

        final settingsFile = File('${root.path}/world_book_settings.json');
        await settingsFile.writeAsString(
          jsonEncode({
            'world_books_v1': jsonEncode([
              {'id': 'shared-book', 'name': 'Imported Shared'},
              {'id': 'remote-book', 'name': 'Remote'},
              {'id': 'remote-book', 'name': 'Remote Duplicate'},
            ]),
            'world_books_active_ids_by_assistant_v1': jsonEncode({
              'assistant-a': ['shared-book', 'remote-book', 'remote-book'],
              'assistant-b': ['remote-book'],
            }),
            'world_books_collapsed_v1': jsonEncode({
              'shared-book': true,
              'remote-book': true,
            }),
          }),
        );

        final zipFile = File('${root.path}/world_book_settings.zip');
        final encoder = ZipFileEncoder();
        encoder.create(zipFile.path);
        encoder.addFileSync(settingsFile, 'settings.json');
        encoder.closeSync();

        final sync = DataSync(chatService: ChatService());
        await sync.restoreFromLocalFile(
          zipFile,
          const WebDavConfig(includeChats: false, includeFiles: false),
          mode: RestoreMode.merge,
        );

        final prefs = await SharedPreferences.getInstance();
        final books = jsonDecode(prefs.getString('world_books_v1')!) as List;
        expect(books.map((book) => (book as Map)['id']), [
          'local-book',
          'shared-book',
          'remote-book',
        ]);
        expect(
          books.where((book) => (book as Map)['id'] == 'shared-book').single,
          {'id': 'shared-book', 'name': 'Local Shared'},
        );

        final activeIds =
            jsonDecode(
                  prefs.getString('world_books_active_ids_by_assistant_v1')!,
                )
                as Map<String, dynamic>;
        expect(activeIds['assistant-a'], [
          'local-book',
          'shared-book',
          'remote-book',
        ]);
        expect(activeIds['assistant-b'], ['remote-book']);

        final collapsed =
            jsonDecode(prefs.getString('world_books_collapsed_v1')!)
                as Map<String, dynamic>;
        expect(collapsed, {
          'local-book': true,
          'shared-book': false,
          'remote-book': true,
        });
      },
    );

    test('cleans temporary restore files when WebDAV restore fails', () async {
      final sourceDir = Directory('${root.path}/source_upload');
      await sourceDir.create(recursive: true);
      final sourceFile = File('${sourceDir.path}/file.txt');
      await sourceFile.writeAsString('payload');

      final zipFile = File('${root.path}/restore_source.zip');
      final encoder = ZipFileEncoder();
      encoder.create(zipFile.path);
      encoder.addFileSync(sourceFile, 'upload/file.txt');
      encoder.closeSync();

      await File('${root.path}/upload').writeAsString('not a directory');

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        await request.response.addStream(zipFile.openRead());
        await request.response.close();
      });

      final sync = DataSync(chatService: ChatService());
      final tmpDir = Directory('${root.path}/tmp');
      final item = BackupFileItem(
        href: Uri.parse('http://127.0.0.1:${server.port}/restore_source.zip'),
        displayName: 'restore_source.zip',
        size: await zipFile.length(),
        lastModified: null,
      );

      await expectLater(
        sync.restoreFromWebDav(
          const WebDavConfig(includeChats: false, includeFiles: true),
          item,
        ),
        throwsA(anything),
      );

      expect(await File('${tmpDir.path}/restore_source.zip').exists(), isFalse);
      expect(await tmpDir.list().toList(), isEmpty);
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Baizi/core/services/backup/data_sync.dart' as backup_sync;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesAsync backup filter', () {
    test('snapshot excludes local-only chat font scale', () async {
      SharedPreferences.setMockInitialValues({
        'display_chat_font_scale_v1': 1.3,
        'display_auto_scroll_enabled_v1': false,
        'desktop_hotkeys_commands_v1': [
          'close_window=cmd+w',
          'open_settings=cmd+comma',
        ],
        'desktop_hotkeys_enabled_v1': ['close_window=1', 'open_settings=1'],
      });

      final prefs = await backup_sync.SharedPreferencesAsync.instance;
      final snapshot = await prefs.snapshot();

      expect(snapshot.containsKey('display_chat_font_scale_v1'), isFalse);
      expect(snapshot.containsKey('desktop_hotkeys_commands_v1'), isFalse);
      expect(snapshot.containsKey('desktop_hotkeys_enabled_v1'), isFalse);
      expect(snapshot['display_auto_scroll_enabled_v1'], isFalse);
    });

    test(
      'snapshot excludes provider configuration and credential entries',
      () async {
        SharedPreferences.setMockInitialValues({
          'provider_configs_v1': '{"openai":{}}',
          'provider_configs_backup_v1': '{"openai":{}}',
          'providers_order_v1': ['openai'],
          'provider_groups_v1': '[]',
          'provider_group_map_v1': '{}',
          'provider_group_collapsed_v1': '{}',
          'provider_ungrouped_position_v1': 0,
          'provider_credentials_v1': 'legacy-secret',
          'baizi_api_key_v1': 'legacy-key',
          'display_show_provider_in_chat_message_v1': true,
          'theme_mode_v1': 'dark',
        });

        final prefs = await backup_sync.SharedPreferencesAsync.instance;
        final snapshot = await prefs.snapshot();

        for (final key in <String>[
          'provider_configs_v1',
          'provider_configs_backup_v1',
          'providers_order_v1',
          'provider_groups_v1',
          'provider_group_map_v1',
          'provider_group_collapsed_v1',
          'provider_ungrouped_position_v1',
          'provider_credentials_v1',
          'baizi_api_key_v1',
        ]) {
          expect(snapshot, isNot(contains(key)), reason: key);
        }
        expect(snapshot['display_show_provider_in_chat_message_v1'], isTrue);
        expect(snapshot['theme_mode_v1'], 'dark');
      },
    );

    test('snapshot sanitizes nested service and backup credentials', () async {
      SharedPreferences.setMockInitialValues({
        'search_services_v1': jsonEncode([
          {
            'type': 'tavily',
            'id': 'search-1',
            'apiKey': 'search-secret',
            'url': 'https://search.example',
          },
        ]),
        'tts_services_v1': jsonEncode([
          {
            'kind': 'openai',
            'id': 'tts-1',
            'apiKey': 'tts-secret',
            'voice': 'alloy',
          },
        ]),
        'mcp_servers_v1': jsonEncode([
          {
            'id': 'mcp-1',
            'headers': {
              'Authorization': 'Bearer mcp-secret',
              'X-Trace-Id': 'trace-1',
            },
            'env': {'PATH': '/usr/bin', 'API_TOKEN': 'mcp-token-secret'},
          },
        ]),
        'webdav_config_v1': jsonEncode({
          'url': 'https://dav.example',
          'password': 'dav-secret',
          'path': 'backups',
        }),
        's3_config_v1': jsonEncode({
          'endpoint': 'https://s3.example',
          'bucket': 'backups',
          'accessKeyId': 's3-access-secret',
          'secretAccessKey': 's3-secret',
        }),
      });

      final prefs = await backup_sync.SharedPreferencesAsync.instance;
      final snapshot = await prefs.snapshot();
      final encoded = jsonEncode(snapshot);

      for (final secret in <String>[
        'search-secret',
        'tts-secret',
        'mcp-secret',
        'mcp-token-secret',
        'dav-secret',
        's3-access-secret',
        's3-secret',
      ]) {
        expect(encoded, isNot(contains(secret)), reason: secret);
      }
      expect(encoded, contains('https://search.example'));
      expect(encoded, contains('alloy'));
      expect(encoded, contains('X-Trace-Id'));
      expect(encoded, contains('/usr/bin'));
      expect(encoded, contains('backups'));
    });

    test('snapshot fails closed for malformed credential settings', () async {
      SharedPreferences.setMockInitialValues({
        'search_services_v1': '{search-secret',
        'tts_services_v1': '{tts-secret',
        'mcp_servers_v1': '{mcp-secret',
        'webdav_config_v1': '{dav-secret',
        's3_config_v1': '{s3-secret',
      });

      final prefs = await backup_sync.SharedPreferencesAsync.instance;
      final snapshot = await prefs.snapshot();

      expect(snapshot['search_services_v1'], '[]');
      expect(snapshot['tts_services_v1'], '[]');
      expect(snapshot['mcp_servers_v1'], '[]');
      expect(snapshot['webdav_config_v1'], '{}');
      expect(snapshot['s3_config_v1'], '{}');
      expect(jsonEncode(snapshot), isNot(contains('secret')));
    });

    test(
      'overwrite restore preserves same-target credentials without seeding new entries',
      () async {
        SharedPreferences.setMockInitialValues({
          'search_services_v1': jsonEncode([
            {
              'id': 'search-shared',
              'type': 'tavily',
              'url': 'https://search.example',
              'apiKey': 'local-search-secret',
              'label': 'Local search',
            },
          ]),
          'tts_services_v1': jsonEncode([
            {
              'id': 'tts-shared',
              'kind': 'openai',
              'baseUrl': 'https://tts.example/v1',
              'apiKey': 'local-tts-secret',
              'voice': 'alloy',
            },
          ]),
          'mcp_servers_v1': jsonEncode([
            {
              'id': 'mcp-shared',
              'transport': 'http',
              'url': 'https://mcp.example',
              'name': 'Local MCP',
              'headers': {
                'Authorization': 'Bearer local-mcp-secret',
                'X-Trace-Id': 'local-trace',
              },
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
            'sessionToken': 'local-session-secret',
          }),
        });

        final prefs = await backup_sync.SharedPreferencesAsync.instance;
        await prefs.restore({
          'search_services_v1': jsonEncode([
            {
              'id': 'search-shared',
              'type': 'tavily',
              'url': 'https://search.example',
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
              'baseUrl': 'https://tts.example/v1',
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
          'mcp_servers_v1': jsonEncode([
            {
              'id': 'mcp-shared',
              'transport': 'http',
              'url': 'https://mcp.example',
              'name': 'Imported MCP',
              'headers': {'Authorization': '', 'X-Trace-Id': 'imported-trace'},
            },
            {
              'id': 'mcp-new',
              'transport': 'http',
              'url': 'https://new-mcp.example',
              'headers': {'Authorization': '<redacted>'},
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
            'sessionToken': '',
          }),
        });

        final rawPrefs = await SharedPreferences.getInstance();
        Map<String, Map<String, dynamic>> listById(String key) {
          final list = jsonDecode(rawPrefs.getString(key)!) as List<dynamic>;
          return <String, Map<String, dynamic>>{
            for (final item in list.cast<Map>())
              item['id'] as String: item.cast<String, dynamic>(),
          };
        }

        final search = listById('search_services_v1');
        expect(search['search-shared']!['apiKey'], 'local-search-secret');
        expect(search['search-shared']!['label'], 'Imported search');
        expect(search['search-new']!['apiKey'], '');

        final tts = listById('tts_services_v1');
        expect(tts['tts-shared']!['apiKey'], 'local-tts-secret');
        expect(tts['tts-shared']!['voice'], 'nova');
        expect(tts['tts-new'], isNot(contains('apiKey')));

        final mcp = listById('mcp_servers_v1');
        expect(mcp['mcp-shared']!['name'], 'Imported MCP');
        expect(
          (mcp['mcp-shared']!['headers'] as Map)['Authorization'],
          'Bearer local-mcp-secret',
        );
        expect(
          (mcp['mcp-shared']!['headers'] as Map)['X-Trace-Id'],
          'imported-trace',
        );
        expect(
          mcp['mcp-new']!['headers'] as Map,
          isNot(contains('Authorization')),
        );

        final webDav =
            jsonDecode(rawPrefs.getString('webdav_config_v1')!) as Map;
        expect(webDav['password'], 'local-dav-secret');
        expect(webDav['username'], 'imported-user');
        expect(webDav['path'], 'imported-backups');

        final s3 = jsonDecode(rawPrefs.getString('s3_config_v1')!) as Map;
        expect(s3['accessKeyId'], 'local-access-key');
        expect(s3['secretAccessKey'], 'local-s3-secret');
        expect(s3['sessionToken'], 'local-session-secret');
        expect(s3['bucket'], 'imported-bucket');
      },
    );

    test(
      'restore ignores chat font scale but restores synced settings',
      () async {
        SharedPreferences.setMockInitialValues({
          'display_chat_font_scale_v1': 1.15,
        });

        final prefs = await backup_sync.SharedPreferencesAsync.instance;
        await prefs.restore({
          'display_chat_font_scale_v1': 1.4,
          'display_auto_scroll_enabled_v1': false,
        });

        final rawPrefs = await SharedPreferences.getInstance();
        expect(rawPrefs.getDouble('display_chat_font_scale_v1'), 1.15);
        expect(rawPrefs.getBool('display_auto_scroll_enabled_v1'), isFalse);
      },
    );

    test('restoreSingle ignores old backup chat font scale entries', () async {
      SharedPreferences.setMockInitialValues({
        'display_chat_font_scale_v1': 0.95,
      });

      final prefs = await backup_sync.SharedPreferencesAsync.instance;
      await prefs.restoreSingle('display_chat_font_scale_v1', 1.5);

      final rawPrefs = await SharedPreferences.getInstance();
      expect(rawPrefs.getDouble('display_chat_font_scale_v1'), 0.95);
    });

    test('restore ignores platform-specific desktop hotkey entries', () async {
      SharedPreferences.setMockInitialValues({
        'desktop_hotkeys_commands_v1': [
          'close_window=ctrl+w',
          'open_settings=ctrl+comma',
        ],
        'desktop_hotkeys_enabled_v1': ['close_window=1', 'open_settings=0'],
      });

      final prefs = await backup_sync.SharedPreferencesAsync.instance;
      await prefs.restore({
        'desktop_hotkeys_commands_v1': [
          'close_window=cmd+w',
          'open_settings=cmd+comma',
        ],
        'desktop_hotkeys_enabled_v1': ['close_window=1', 'open_settings=1'],
      });

      final rawPrefs = await SharedPreferences.getInstance();
      expect(rawPrefs.getStringList('desktop_hotkeys_commands_v1'), [
        'close_window=ctrl+w',
        'open_settings=ctrl+comma',
      ]);
      expect(rawPrefs.getStringList('desktop_hotkeys_enabled_v1'), [
        'close_window=1',
        'open_settings=0',
      ]);
    });
  });
}

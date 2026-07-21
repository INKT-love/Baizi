import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Baizi/core/config/baizi_gateway.dart';
import 'package:Baizi/core/providers/settings_provider.dart';
import 'package:Baizi/core/services/model_catalog_service.dart';
import 'package:Baizi/core/services/secure_api_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider Baizi gateway migration', () {
    test(
      'moves a legacy key to secure storage and removes the old host',
      () async {
        final legacyConfig = <String, Object?>{
          'LegacyClaude': <String, Object?>{
            'id': 'LegacyClaude',
            'enabled': true,
            'name': 'Legacy Claude',
            'apiKey': 'legacy-secret',
            'baseUrl': 'https://attacker.invalid/v1',
            'providerType': 'claude',
            'models': <String>['claude-sonnet-4-5'],
            'modelOverrides': <String, Object?>{},
          },
        };
        SharedPreferences.setMockInitialValues(<String, Object>{
          'provider_configs_v1': jsonEncode(legacyConfig),
          'selected_model_v1': 'LegacyClaude::claude-sonnet-4-5',
          'pinned_models_v1': <String>['LegacyClaude::claude-sonnet-4-5'],
          'baizi_models_cache_v1': <String>['claude-sonnet-4-5'],
        });
        final backend = _MemoryBackend();
        final settings = SettingsProvider(
          apiKeyStore: SecureApiKeyStore(backend: backend),
        );

        await settings.initialization;

        expect(
          await SecureApiKeyStore(backend: backend).read(),
          'legacy-secret',
        );
        expect(settings.hasBaiziApiKey, isTrue);
        expect(settings.providerConfigs.keys, <String>[
          BaiziGateway.providerId,
        ]);
        expect(settings.baiziProviderConfig.baseUrl, BaiziGateway.baseUrl);
        expect(settings.baiziProviderConfig.apiKey, 'legacy-secret');
        expect(
          settings.getProviderConfig(BaiziGateway.providerId).apiKey,
          isEmpty,
        );
        expect(
          settings.providerConfigs[BaiziGateway.providerId]!.apiKey,
          isEmpty,
        );
        expect(settings.currentModelProvider, BaiziGateway.providerId);
        expect(settings.currentModelId, 'claude-sonnet-4-5');
        expect(
          settings.isModelPinned('LegacyClaude', 'claude-sonnet-4-5'),
          isTrue,
        );

        final prefs = await SharedPreferences.getInstance();
        final persisted = prefs.getString('provider_configs_v1')!;
        expect(persisted, isNot(contains('legacy-secret')));
        expect(persisted, isNot(contains('attacker.invalid')));
        expect(persisted, contains(BaiziGateway.baseUrl));
        expect(
          prefs.getString('selected_model_v1'),
          '${BaiziGateway.providerId}::claude-sonnet-4-5',
        );
      },
    );

    test('does not use a plaintext key when secure storage fails', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'provider_configs_v1': jsonEncode(<String, Object?>{
          'OpenAI': <String, Object?>{
            'id': 'OpenAI',
            'enabled': true,
            'name': 'OpenAI',
            'apiKey': 'plaintext-secret',
            'baseUrl': 'https://api.openai.com/v1',
            'providerType': 'openai',
            'models': <String>['gpt-5'],
          },
        }),
      });
      final settings = SettingsProvider(
        apiKeyStore: SecureApiKeyStore(backend: _FailingBackend()),
      );

      await settings.initialization;

      expect(settings.isLoaded, isTrue);
      expect(settings.apiKeyStorageError, isA<StateError>());
      expect(settings.hasBaiziApiKey, isFalse);
      expect(settings.baiziProviderConfig.apiKey, isEmpty);
    });

    test('persists fetched models without persisting the secure key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final backend = _MemoryBackend();
      final settings = SettingsProvider(
        apiKeyStore: SecureApiKeyStore(backend: backend),
      );
      await settings.initialization;
      await settings.setBaiziApiKey('new-secret');
      final client = MockClient((request) async {
        expect(request.url, BaiziGateway.modelsUri);
        expect(request.headers['Authorization'], 'Bearer new-secret');
        return http.Response(
          jsonEncode(<String, Object?>{
            'data': <Map<String, String>>[
              <String, String>{'id': 'gpt-5'},
              <String, String>{'id': 'claude-opus-4-1'},
            ],
          }),
          200,
        );
      });

      final models = await settings.refreshBaiziModels(client: client);
      await settings.setCurrentModel('ignored-provider', 'gpt-5');

      expect(models, <String>['gpt-5', 'claude-opus-4-1']);
      expect(settings.hasCompleteBaiziSetup, isTrue);
      expect(settings.currentModelProvider, BaiziGateway.providerId);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('baizi_models_cache_v1'), models);
      expect(
        prefs.getString('provider_configs_v1'),
        isNot(contains('new-secret')),
      );
      expect(
        prefs.getString('selected_model_v1'),
        '${BaiziGateway.providerId}::gpt-5',
      );
    });

    test('validates a replacement key before changing working setup', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'baizi_models_cache_v1': <String>['gpt-old'],
        'selected_model_v1': '${BaiziGateway.providerId}::gpt-old',
      });
      final backend = _MemoryBackend()
        ..values[SecureApiKeyStore.storageKey] = 'working-key';
      final settings = SettingsProvider(
        apiKeyStore: SecureApiKeyStore(backend: backend),
      );
      await settings.initialization;

      await expectLater(
        settings.configureBaiziApiKey(
          'bad-key',
          client: MockClient((request) async => http.Response('', 401)),
        ),
        throwsA(isA<Exception>()),
      );

      expect(await SecureApiKeyStore(backend: backend).read(), 'working-key');
      expect(settings.baiziProviderConfig.apiKey, 'working-key');
      expect(settings.baiziModels, <String>['gpt-old']);
      expect(settings.currentModelId, 'gpt-old');
    });

    test('commits a validated key and records recent model choices', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final backend = _MemoryBackend();
      final settings = SettingsProvider(
        apiKeyStore: SecureApiKeyStore(backend: backend),
      );
      await settings.initialization;
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer candidate-key');
        return http.Response(
          jsonEncode(<String, Object?>{
            'data': <Map<String, String>>[
              <String, String>{'id': 'gpt-5'},
              <String, String>{'id': 'claude-sonnet-4-6'},
            ],
          }),
          200,
        );
      });

      final models = await settings.configureBaiziApiKey(
        ' candidate-key ',
        client: client,
      );
      await settings.setCurrentModel('ignored', 'gpt-5');
      await settings.setCurrentModel('ignored', 'claude-sonnet-4-6');
      await settings.setCurrentModel('ignored', 'gpt-5');

      expect(models, <String>['gpt-5', 'claude-sonnet-4-6']);
      expect(await SecureApiKeyStore(backend: backend).read(), 'candidate-key');
      expect(settings.recentBaiziModels, <String>[
        'gpt-5',
        'claude-sonnet-4-6',
      ]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('baizi_recent_models_v1'), <String>[
        'gpt-5',
        'claude-sonnet-4-6',
      ]);
      expect(
        prefs.getString('provider_configs_v1'),
        isNot(contains('candidate-key')),
      );
    });

    test('adds a validated key profile and makes it active', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final backend = _MemoryBackend();
      final settings = SettingsProvider(
        apiKeyStore: SecureApiKeyStore(backend: backend),
      );
      await settings.initialization;

      await settings.configureBaiziApiKey(
        'primary-key',
        client: _modelsClientFor('primary-key', <String>['gpt-5']),
      );
      await settings.addBaiziApiKeyProfile(
        '备用 Key',
        'backup-key',
        client: _modelsClientFor('backup-key', <String>['claude-sonnet-4-6']),
      );

      expect(
        settings.baiziApiKeyProfiles.map((profile) => profile.label),
        <String>['Key 1', '备用 Key'],
      );
      expect(settings.activeBaiziApiKeyProfileLabel, '备用 Key');
      expect(settings.baiziModels, <String>['claude-sonnet-4-6']);
      expect(await SecureApiKeyStore(backend: backend).read(), 'backup-key');
    });

    test(
      'keeps the current key when switching to an invalid saved key',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final backend = _MemoryBackend();
        final store = SecureApiKeyStore(backend: backend);
        final settings = SettingsProvider(apiKeyStore: store);
        await settings.initialization;

        await settings.configureBaiziApiKey(
          'working-key',
          client: _modelsClientFor('working-key', <String>['gpt-5']),
        );
        final vault = await store.addProfile(
          id: 'invalid-backup',
          label: 'Invalid backup',
          key: 'invalid-key',
          activate: false,
        );
        expect(vault.activeProfile?.label, 'Key 1');

        await expectLater(
          settings.selectBaiziApiKeyProfile(
            'invalid-backup',
            client: MockClient((_) async => http.Response('', 401)),
          ),
          throwsA(isA<ModelCatalogException>()),
        );

        expect(settings.activeBaiziApiKeyProfileLabel, 'Key 1');
        expect(settings.baiziModels, <String>['gpt-5']);
        expect(await store.read(), 'working-key');
      },
    );

    test('deleting the active key switches to another validated key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final backend = _MemoryBackend();
      final store = SecureApiKeyStore(backend: backend);
      final settings = SettingsProvider(apiKeyStore: store);
      await settings.initialization;

      await settings.configureBaiziApiKey(
        'primary-key',
        client: _modelsClientFor('primary-key', <String>['gpt-5']),
      );
      await store.addProfile(
        id: 'backup',
        label: 'Backup',
        key: 'backup-key',
        activate: false,
      );

      final activeId = settings.activeBaiziApiKeyProfileId!;
      await settings.deleteBaiziApiKeyProfile(
        activeId,
        client: _modelsClientFor('backup-key', <String>['claude-opus-4-1']),
      );

      expect(settings.baiziApiKeyProfiles, hasLength(1));
      expect(settings.activeBaiziApiKeyProfileLabel, 'Backup');
      expect(settings.baiziModels, <String>['claude-opus-4-1']);
      expect(await store.read(), 'backup-key');
    });
  });
}

http.Client _modelsClientFor(String expectedKey, List<String> models) {
  return MockClient((request) async {
    expect(request.url, BaiziGateway.modelsUri);
    expect(request.headers['Authorization'], 'Bearer $expectedKey');
    return http.Response(
      jsonEncode(<String, Object?>{
        'data': models.map((model) => <String, String>{'id': model}).toList(),
      }),
      200,
    );
  });
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

final class _FailingBackend implements SecureApiKeyBackend {
  Never _fail() => throw StateError('secure storage unavailable');

  @override
  Future<void> delete(String key) async => _fail();

  @override
  Future<String?> read(String key) async => _fail();

  @override
  Future<void> write(String key, String value) async => _fail();
}

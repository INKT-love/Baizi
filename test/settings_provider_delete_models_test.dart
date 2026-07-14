import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/config/baizi_gateway.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/secure_api_key_store.dart';

Future<SettingsProvider> _settings() async {
  SharedPreferences.setMockInitialValues(const <String, Object>{
    'baizi_models_cache_v1': <String>['keep', 'remove-a', 'remove-b'],
  });
  final settings = SettingsProvider(
    apiKeyStore: SecureApiKeyStore(backend: _MemorySecureApiKeyBackend()),
  );
  await settings.initialization;
  await settings.setProviderConfig(
    BaiziGateway.providerId,
    settings.baiziProviderConfig.copyWith(
      modelOverrides: const {
        'keep': {'name': 'Keep'},
        'remove-a': {'name': 'Remove A'},
        'remove-b': {'name': 'Remove B'},
      },
    ),
  );
  return settings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider model deletion', () {
    test('deleteModels removes selected models and their overrides', () async {
      final settings = await _settings();

      final deleted = await settings.deleteModels(
        BaiziGateway.providerId,
        const {'remove-a', 'remove-b'},
      );

      final cfg = settings.getProviderConfig(BaiziGateway.providerId);
      expect(deleted, 2);
      expect(cfg.models, const ['keep']);
      expect(cfg.modelOverrides.keys, const ['keep']);
    });

    test('deleteModels does nothing for empty selection', () async {
      final settings = await _settings();

      final deleted = await settings.deleteModels(
        BaiziGateway.providerId,
        const <String>{},
      );

      final cfg = settings.getProviderConfig(BaiziGateway.providerId);
      expect(deleted, 0);
      expect(cfg.models, const ['keep', 'remove-a', 'remove-b']);
      expect(cfg.modelOverrides.keys, const ['keep', 'remove-a', 'remove-b']);
    });

    test('deleteModels clears selections for deleted models only', () async {
      final settings = await _settings();
      await settings.setCurrentModel(BaiziGateway.providerId, 'remove-a');
      await settings.setTitleModel(BaiziGateway.providerId, 'keep');

      final deleted = await settings.deleteModels(
        BaiziGateway.providerId,
        const {'remove-a'},
      );

      expect(deleted, 1);
      expect(settings.currentModelProvider, isNull);
      expect(settings.currentModelId, isNull);
      expect(settings.titleModelProvider, BaiziGateway.providerId);
      expect(settings.titleModelId, 'keep');
      expect(settings.currentModelId, isNot('keep'));
    });

    test(
      'deleteModels clears orphan overrides when every model is removed',
      () async {
        final settings = await _settings();
        await settings.setProviderConfig(
          BaiziGateway.providerId,
          settings
              .getProviderConfig(BaiziGateway.providerId)
              .copyWith(
                modelOverrides: const {
                  'keep': {'name': 'Keep'},
                  'remove-a': {'name': 'Remove A'},
                  'remove-b': {'name': 'Remove B'},
                  'orphan': {'name': 'Orphan'},
                },
              ),
        );

        final deleted = await settings.deleteModels(
          BaiziGateway.providerId,
          const {'keep', 'remove-a', 'remove-b'},
        );

        final cfg = settings.getProviderConfig(BaiziGateway.providerId);
        expect(deleted, 3);
        expect(cfg.models, isEmpty);
        expect(cfg.modelOverrides, isEmpty);
      },
    );
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

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Baizi/core/config/baizi_gateway.dart';
import 'package:Baizi/core/providers/settings_provider.dart';
import 'package:Baizi/core/services/secure_api_key_store.dart';

Future<SettingsProvider> _settings(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final settings = SettingsProvider(
    apiKeyStore: SecureApiKeyStore(backend: _MemorySecureApiKeyBackend()),
  );
  await settings.initialization;
  return settings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider chat suggestions', () {
    test('defaults suggestion model to disabled', () async {
      final settings = await _settings(const <String, Object>{});

      expect(settings.suggestionModelProvider, isNull);
      expect(settings.suggestionModelId, isNull);
      expect(settings.suggestionModelKey, isNull);
      expect(
        settings.suggestionPrompt,
        SettingsProvider.defaultSuggestionPrompt,
      );
    });

    test('persists selected suggestion model and prompt', () async {
      final settings = await _settings(const <String, Object>{});
      await settings.setSuggestionModel('ignored-provider', 'gpt-test');
      await settings.setSuggestionPrompt('Custom {content} {locale}');

      expect(settings.suggestionModelProvider, BaiziGateway.providerId);
      expect(settings.suggestionModelId, 'gpt-test');
      expect(
        settings.suggestionModelKey,
        '${BaiziGateway.providerId}::gpt-test',
      );
      expect(settings.suggestionPrompt, 'Custom {content} {locale}');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('suggestion_model_v1'),
        '${BaiziGateway.providerId}::gpt-test',
      );
      expect(
        prefs.getString('suggestion_prompt_v1'),
        'Custom {content} {locale}',
      );
    });

    test('defaults suggestion tap to auto-send', () async {
      final settings = await _settings(const <String, Object>{});

      expect(settings.insertSuggestionOnTapOnly, isFalse);
    });

    test('loads and persists insert-only suggestion tap mode', () async {
      final settings = await _settings(<String, Object>{
        'suggestion_insert_on_tap_only_v1': true,
      });

      expect(settings.insertSuggestionOnTapOnly, isTrue);

      await settings.setInsertSuggestionOnTapOnly(false);

      expect(settings.insertSuggestionOnTapOnly, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('suggestion_insert_on_tap_only_v1'), isFalse);
    });

    test(
      'normalizes a legacy suggestion model before clearing Baizi selections',
      () async {
        final settings = await _settings(<String, Object>{
          'baizi_models_cache_v1': <String>['gpt-test'],
          'suggestion_model_v1': 'OpenAI::gpt-test',
        });

        expect(settings.suggestionModelProvider, BaiziGateway.providerId);
        await settings.clearSelectionsForProvider(BaiziGateway.providerId);

        expect(settings.suggestionModelProvider, isNull);
        expect(settings.suggestionModelId, isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('suggestion_model_v1'), isNull);
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

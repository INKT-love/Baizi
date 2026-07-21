import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Baizi/core/config/baizi_gateway.dart';
import 'package:Baizi/core/providers/model_provider.dart';
import 'package:Baizi/core/providers/settings_provider.dart';
import 'package:Baizi/core/services/secure_api_key_store.dart';

Future<SettingsProvider> _settings([
  Map<String, Object> values = const <String, Object>{},
]) async {
  SharedPreferences.setMockInitialValues(values);
  final settings = SettingsProvider(
    apiKeyStore: SecureApiKeyStore(backend: _MemorySecureApiKeyBackend()),
  );
  await settings.initialization;
  return settings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider reasoning support', () {
    test('default Claude and OpenRouter presets do not add latest models', () {
      final claude = ProviderConfig.defaultsFor('Claude');
      final openRouter = ProviderConfig.defaultsFor('OpenRouter');

      expect(claude.models, isEmpty);
      expect(claude.modelOverrides, isEmpty);
      expect(openRouter.models, isEmpty);
      expect(openRouter.modelOverrides, isEmpty);
    });

    test('default Zhipu preset stays user-configured only', () {
      final zhipu = ProviderConfig.defaultsFor('Zhipu AI');

      expect(zhipu.baseUrl, 'https://open.bigmodel.cn/api/paas/v4');
      expect(zhipu.models, isEmpty);
      expect(zhipu.modelOverrides, isEmpty);
    });

    test('default Moonshot preset stays user-configured only', () {
      final moonshot = ProviderConfig.defaultsFor('Moonshot');

      expect(moonshot.baseUrl, 'https://api.moonshot.cn/v1');
      expect(moonshot.models, isEmpty);
      expect(moonshot.modelOverrides, isEmpty);
    });

    test('exposes only Baizi despite a legacy provider order', () async {
      final settings = await _settings(<String, Object>{
        'providers_order_v1': <String>['OpenAI', 'Zhipu AI', 'Grok'],
      });

      expect(settings.providersOrder.first, BaiziGateway.providerId);
      expect(settings.providerConfigs.keys, const <String>[
        BaiziGateway.providerId,
      ]);
      expect(settings.providersOrder, isNot(contains('Kimi')));
    });

    test('latest GLM and Kimi model ids infer expected capabilities', () {
      final glm = ModelRegistry.infer(
        ModelInfo(id: 'glm-5.2', displayName: 'glm-5.2'),
      );
      final kimi = ModelRegistry.infer(
        ModelInfo(id: 'kimi-k2.7-code', displayName: 'kimi-k2.7-code'),
      );

      expect(glm.input, const [Modality.text]);
      expect(glm.output, const [Modality.text]);
      expect(
        glm.abilities,
        containsAll([ModelAbility.tool, ModelAbility.reasoning]),
      );
      expect(kimi.input, contains(Modality.image));
      expect(kimi.output, const [Modality.text]);
      expect(
        kimi.abilities,
        containsAll([ModelAbility.tool, ModelAbility.reasoning]),
      );
    });

    test('Baizi chooses protocol exclusively from the model id', () {
      expect(
        BaiziGateway.protocolForModel('anthropic/claude-fable-5'),
        BaiziApiProtocol.anthropic,
      );
      expect(BaiziGateway.protocolForModel('gpt-5.2'), BaiziApiProtocol.openAi);
    });

    test('Baizi resolves apiModelId before the DeepSeek xhigh check', () async {
      final settings = await _settings(<String, Object>{
        'baizi_models_cache_v1': <String>['pro-alias'],
      });
      await settings.setProviderConfig(
        BaiziGateway.providerId,
        settings.baiziProviderConfig.copyWith(
          modelOverrides: const {
            'pro-alias': {
              'apiModelId': 'deepseek-v4-pro',
              'type': 'chat',
              'input': ['text'],
              'output': ['text'],
              'abilities': ['reasoning'],
            },
          },
        ),
      );

      expect(
        settings.supportsXhighReasoning(BaiziGateway.providerId, 'pro-alias'),
        isTrue,
      );
    });

    group('title generation thinking', () {
      test(
        'defaults to enabled and preserves existing budget fallback',
        () async {
          final settings = await _settings(<String, Object>{
            'thinking_budget_v1': 16000,
          });

          expect(settings.titleGenerationThinkingEnabled, isTrue);
          expect(settings.titleGenerationThinkingBudgetFor(null), 16000);
          expect(settings.titleGenerationThinkingBudgetFor(1024), 1024);
        },
      );

      test(
        'disabled title generation thinking resolves to off budget',
        () async {
          final settings = await _settings();
          await settings.setThinkingBudget(16000);
          await settings.setTitleGenerationThinkingEnabled(false);

          expect(settings.titleGenerationThinkingEnabled, isFalse);
          expect(settings.titleGenerationThinkingBudgetFor(null), 0);
          expect(settings.titleGenerationThinkingBudgetFor(1024), 0);

          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs.getBool('title_generation_thinking_enabled_v1'),
            isFalse,
          );
        },
      );

      test('loads persisted disabled state', () async {
        final settings = await _settings(<String, Object>{
          'title_generation_thinking_enabled_v1': false,
        });

        expect(settings.titleGenerationThinkingEnabled, isFalse);
        expect(settings.titleGenerationThinkingBudgetFor(32000), 0);
      });

      test('reset restores enabled fallback behavior', () async {
        final settings = await _settings(<String, Object>{
          'title_generation_thinking_enabled_v1': false,
          'thinking_budget_v1': 64000,
        });
        await settings.resetTitleGenerationThinkingEnabled();

        expect(settings.titleGenerationThinkingEnabled, isTrue);
        expect(settings.titleGenerationThinkingBudgetFor(null), 64000);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('title_generation_thinking_enabled_v1'), isTrue);
      });
    });

    test(
      'Baizi Claude models expose xhigh and max reasoning without presets',
      () async {
        final settings = await _settings(const <String, Object>{
          'baizi_models_cache_v1': <String>[
            'claude-fable-5',
            'claude-opus-4-8',
          ],
        });

        for (final model in const ['claude-fable-5', 'claude-opus-4-8']) {
          expect(
            settings.supportsXhighReasoning(BaiziGateway.providerId, model),
            isTrue,
          );
          expect(
            settings.supportsMaxReasoning(BaiziGateway.providerId, model),
            isTrue,
          );
        }
        expect(settings.getProviderConfig(BaiziGateway.providerId).models, [
          'claude-fable-5',
          'claude-opus-4-8',
        ]);
      },
    );

    test('Baizi model-name routing exposes Claude max reasoning', () async {
      final settings = await _settings(const <String, Object>{
        'baizi_models_cache_v1': <String>['anthropic/claude-fable-5'],
      });

      expect(
        settings.supportsXhighReasoning(
          BaiziGateway.providerId,
          'anthropic/claude-fable-5',
        ),
        isTrue,
      );
      expect(
        settings.supportsMaxReasoning(
          BaiziGateway.providerId,
          'anthropic/claude-fable-5',
        ),
        isTrue,
      );
    });
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

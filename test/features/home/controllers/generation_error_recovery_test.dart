import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/config/baizi_gateway.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/secure_api_key_store.dart';
import 'package:Kelivo/features/home/controllers/generation_error_recovery.dart';

void main() {
  group('generation error recovery', () {
    test('routes authentication failures to API key setup', () {
      expect(
        classifyGenerationError(ChatApiHttpException(401, 'unauthorized')),
        GenerationErrorRecovery.invalidApiKey,
      );
      expect(
        classifyGenerationError(ChatApiHttpException(403, 'forbidden')),
        GenerationErrorRecovery.forbiddenApiKey,
      );
      expect(
        classifyGenerationError(
          const BaiziGatewayException(BaiziGatewayFailureType.missingApiKey),
        ),
        GenerationErrorRecovery.invalidApiKey,
      );
    });

    test('routes missing and unavailable models to model selection', () {
      expect(
        classifyGenerationError(
          const BaiziGatewayException(
            BaiziGatewayFailureType.modelUnavailable,
            modelId: 'removed-model',
          ),
        ),
        GenerationErrorRecovery.chooseModel,
      );
      expect(
        classifyGenerationError('no_model'),
        GenerationErrorRecovery.chooseModel,
      );
    });

    test('keeps unrelated failures on the generic error path', () {
      expect(
        classifyGenerationError(ChatApiHttpException(500, 'server error')),
        GenerationErrorRecovery.none,
      );
      expect(
        classifyGenerationError(StateError('network failed')),
        GenerationErrorRecovery.none,
      );
    });

    test('routes stale model HTTP failures to model selection', () {
      expect(
        classifyGenerationError(ChatApiHttpException(404, 'not found')),
        GenerationErrorRecovery.chooseModel,
      );
      expect(
        classifyGenerationError(
          ChatApiHttpException(
            400,
            '{"error":{"code":"model_not_found",'
            '"message":"The requested model does not exist"}}',
          ),
        ),
        GenerationErrorRecovery.chooseModel,
      );
      expect(
        classifyGenerationError(
          ChatApiHttpException(400, '{"error":{"message":"Bad input"}}'),
        ),
        GenerationErrorRecovery.none,
      );
    });
  });

  group('recovery model selection', () {
    test('updates and persists an explicit current-assistant model', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'assistants_v1': Assistant.encodeList(const <Assistant>[
          Assistant(
            id: 'assistant',
            name: 'Assistant',
            chatModelProvider: BaiziGateway.providerId,
            chatModelId: 'stale-model',
          ),
        ]),
        'current_assistant_id_v1': 'assistant',
        'baizi_models_cache_v1': <String>['global-model', 'fresh-model'],
        'selected_model_v1': '${BaiziGateway.providerId}::global-model',
      });
      final settings = SettingsProvider(
        apiKeyStore: SecureApiKeyStore(backend: _MemoryBackend()),
      );
      addTearDown(settings.dispose);
      await settings.initialization;
      final assistants = AssistantProvider();
      addTearDown(assistants.dispose);
      await _waitUntil(() => assistants.assistants.length == 1);

      expect(
        recoveryModelSelectionInitialId(settings, assistants),
        'stale-model',
      );

      await applyRecoveryModelSelection(
        settings: settings,
        assistants: assistants,
        modelId: 'fresh-model',
      );

      expect(settings.currentModelId, 'global-model');
      expect(
        assistants.currentAssistant?.chatModelProvider,
        BaiziGateway.providerId,
      );
      expect(assistants.currentAssistant?.chatModelId, 'fresh-model');
      final prefs = await SharedPreferences.getInstance();
      final persisted = Assistant.decodeList(
        prefs.getString('assistants_v1')!,
      ).single;
      expect(persisted.chatModelProvider, BaiziGateway.providerId);
      expect(persisted.chatModelId, 'fresh-model');
    });

    test('updates the global model when the assistant inherits it', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'assistants_v1': Assistant.encodeList(const <Assistant>[
          Assistant(id: 'assistant', name: 'Assistant'),
        ]),
        'current_assistant_id_v1': 'assistant',
        'baizi_models_cache_v1': <String>['global-model', 'fresh-model'],
        'selected_model_v1': '${BaiziGateway.providerId}::global-model',
      });
      final settings = SettingsProvider(
        apiKeyStore: SecureApiKeyStore(backend: _MemoryBackend()),
      );
      addTearDown(settings.dispose);
      await settings.initialization;
      final assistants = AssistantProvider();
      addTearDown(assistants.dispose);
      await _waitUntil(() => assistants.assistants.length == 1);

      expect(
        recoveryModelSelectionInitialId(settings, assistants),
        'global-model',
      );

      await applyRecoveryModelSelection(
        settings: settings,
        assistants: assistants,
        modelId: 'fresh-model',
      );

      expect(settings.currentModelProvider, BaiziGateway.providerId);
      expect(settings.currentModelId, 'fresh-model');
      expect(assistants.currentAssistant?.chatModelProvider, isNull);
      expect(assistants.currentAssistant?.chatModelId, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('selected_model_v1'),
        '${BaiziGateway.providerId}::fresh-model',
      );
    });
  });
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for AssistantProvider initialization.');
}

final class _MemoryBackend implements SecureApiKeyBackend {
  final Map<String, String> values = <String, String>{
    SecureApiKeyStore.storageKey: 'test-key',
  };

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

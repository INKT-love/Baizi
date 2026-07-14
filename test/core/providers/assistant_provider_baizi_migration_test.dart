import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/config/baizi_gateway.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for AssistantProvider initialization.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssistantProvider Baizi provider migration', () {
    test(
      'normalizes legacy providers, preserves model ids, and is idempotent',
      () async {
        final source = <Assistant>[
          const Assistant(
            id: 'legacy-openai',
            name: 'Legacy OpenAI',
            chatModelProvider: 'OpenAI',
            chatModelId: 'gpt-5',
          ),
          const Assistant(
            id: 'legacy-claude',
            name: 'Legacy Claude',
            chatModelProvider: 'BAIZI',
            chatModelId: 'claude-sonnet-4-6',
          ),
          const Assistant(
            id: 'inherited',
            name: 'Global model',
            chatModelId: 'deepseek-chat',
          ),
        ];
        final originalRaw = Assistant.encodeList(source);
        SharedPreferences.setMockInitialValues(<String, Object>{
          'assistants_v1': originalRaw,
        });
        final prefs = await SharedPreferences.getInstance();

        final first = AssistantProvider();
        await _waitUntil(() {
          final raw = prefs.getString('assistants_v1');
          return first.assistants.length == source.length && raw != originalRaw;
        });

        expect(
          first.getById('legacy-openai')?.chatModelProvider,
          BaiziGateway.providerId,
        );
        expect(first.getById('legacy-openai')?.chatModelId, 'gpt-5');
        expect(
          first.getById('legacy-claude')?.chatModelProvider,
          BaiziGateway.providerId,
        );
        expect(
          first.getById('legacy-claude')?.chatModelId,
          'claude-sonnet-4-6',
        );
        expect(first.getById('inherited')?.chatModelProvider, isNull);
        expect(first.getById('inherited')?.chatModelId, 'deepseek-chat');

        final migratedRaw = prefs.getString('assistants_v1')!;
        final second = AssistantProvider();
        await _waitUntil(() => second.assistants.length == source.length);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(prefs.getString('assistants_v1'), migratedRaw);
        expect(
          second.getById('legacy-openai')?.chatModelProvider,
          BaiziGateway.providerId,
        );
      },
    );

    test('normalizes legacy provider values at the update boundary', () async {
      const source = Assistant(id: 'assistant', name: 'Assistant');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'assistants_v1': Assistant.encodeList(const <Assistant>[source]),
      });
      final provider = AssistantProvider();
      await _waitUntil(() => provider.assistants.length == 1);

      await provider.updateAssistant(
        source.copyWith(
          chatModelProvider: 'Anthropic',
          chatModelId: 'claude-opus-4-1',
        ),
      );

      expect(
        provider.currentAssistant?.chatModelProvider,
        BaiziGateway.providerId,
      );
      expect(provider.currentAssistant?.chatModelId, 'claude-opus-4-1');
      final prefs = await SharedPreferences.getInstance();
      expect(
        Assistant.decodeList(
          prefs.getString('assistants_v1')!,
        ).single.chatModelProvider,
        BaiziGateway.providerId,
      );
    });

    test(
      'removes protected custom request data from local persistence',
      () async {
        const source = Assistant(
          id: 'legacy-custom-request',
          name: 'Legacy Custom Request',
          customHeaders: <Map<String, String>>[
            <String, String>{'name': 'Authorization', 'value': 'Bearer unsafe'},
            <String, String>{'name': 'content_type', 'value': 'text/plain'},
            <String, String>{'name': 'Api-Key', 'value': 'unsafe-api-key'},
            <String, String>{
              'name': 'X-Access-Token',
              'value': 'unsafe-access-token',
            },
            <String, String>{'name': '', 'value': 'possibly-secret'},
            <String, String>{'name': 'X-Trace-Id', 'value': 'trace-1'},
          ],
          customBody: <Map<String, String>>[
            <String, String>{'key': 'model', 'value': 'unsafe-model'},
            <String, String>{'key': 'apiKey', 'value': 'sk-unsafe'},
            <String, String>{'key': 'customToken', 'value': 'unsafe-token'},
            <String, String>{'key': '', 'value': 'possibly-secret'},
            <String, String>{'key': 'max_tokens', 'value': '4096'},
            <String, String>{
              'key': 'metadata',
              'value': '{"request_id":"request-1"}',
            },
          ],
        );
        final originalRaw = Assistant.encodeList(const <Assistant>[source]);
        SharedPreferences.setMockInitialValues(<String, Object>{
          'assistants_v1': originalRaw,
        });
        final prefs = await SharedPreferences.getInstance();

        final provider = AssistantProvider();
        await _waitUntil(() {
          final raw = prefs.getString('assistants_v1');
          return provider.assistants.length == 1 && raw != originalRaw;
        });

        final assistant = provider.assistants.single;
        expect(assistant.customHeaders, const <Map<String, String>>[
          <String, String>{'name': 'X-Trace-Id', 'value': 'trace-1'},
        ]);
        expect(assistant.customBody, const <Map<String, String>>[
          <String, String>{'key': 'max_tokens', 'value': '4096'},
          <String, String>{
            'key': 'metadata',
            'value': '{"request_id":"request-1"}',
          },
        ]);

        final persistedRaw = prefs.getString('assistants_v1')!;
        expect(persistedRaw, isNot(contains('unsafe')));
        expect(persistedRaw, isNot(contains('possibly-secret')));
        final persisted = Assistant.decodeList(persistedRaw).single;
        expect(persisted.customHeaders, assistant.customHeaders);
        expect(persisted.customBody, assistant.customBody);
      },
    );

    test('leaves malformed persisted data untouched', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'assistants_v1': '{malformed',
      });
      final provider = AssistantProvider();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(provider.assistants, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('assistants_v1'), '{malformed');
    });
  });
}

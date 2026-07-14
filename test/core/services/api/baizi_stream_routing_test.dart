import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:Kelivo/core/config/baizi_gateway.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/network/request_logger.dart';

ProviderConfig _hostileBaiziConfig(String modelId) {
  return ProviderConfig(
    id: BaiziGateway.providerId,
    enabled: true,
    name: 'Baizi',
    apiKey: 'safe-key',
    baseUrl: 'https://attacker.invalid/v9',
    providerType: ProviderKind.google,
    chatPath: '/responses',
    useResponseApi: true,
    vertexAI: true,
    models: <String>[modelId],
    modelOverrides: <String, dynamic>{
      modelId: <String, dynamic>{
        'apiModelId': 'attacker-model',
        'headers': <Map<String, String>>[
          <String, String>{
            'name': 'Authorization',
            'value': 'Bearer attacker-key',
          },
          <String, String>{'name': 'x-api-key', 'value': 'attacker-key'},
          <String, String>{'name': 'X-Trace-Id', 'value': 'trace-model'},
        ],
        'body': <Map<String, String>>[
          <String, String>{'key': 'model', 'value': 'attacker-model'},
          <String, String>{'key': 'stream', 'value': 'false'},
          <String, String>{'key': 'messages', 'value': '[]'},
          <String, String>{'key': 'temperature', 'value': '0.2'},
        ],
      },
    },
  );
}

void main() {
  group('Baizi production stream routing', () {
    test('blocks missing credentials and unavailable models before I/O', () {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('', 500);
      });

      expect(
        ChatApiService.sendMessageStream(
          config: _hostileBaiziConfig('gpt-5').copyWith(apiKey: ''),
          modelId: 'gpt-5',
          messages: const <Map<String, dynamic>>[],
          client: client,
        ).toList,
        throwsA(
          isA<BaiziGatewayException>().having(
            (error) => error.type,
            'type',
            BaiziGatewayFailureType.missingApiKey,
          ),
        ),
      );
      expect(
        ChatApiService.sendMessageStream(
          config: _hostileBaiziConfig('gpt-5'),
          modelId: 'removed-model',
          messages: const <Map<String, dynamic>>[],
          client: client,
        ).toList,
        throwsA(
          isA<BaiziGatewayException>().having(
            (error) => error.type,
            'type',
            BaiziGatewayFailureType.modelUnavailable,
          ),
        ),
      );
      expect(requests, 0);
    });

    test('forces non-Claude models through OpenAI Chat Completions', () async {
      const modelId = 'gpt-image-1';
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          'data: {"choices":[{"delta":{"content":"O"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"K"},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: <String, String>{'content-type': 'text/event-stream'},
        );
      });

      final chunks = await ChatApiService.sendMessageStream(
        config: _hostileBaiziConfig(modelId),
        modelId: modelId,
        messages: const <Map<String, dynamic>>[
          <String, dynamic>{'role': 'user', 'content': 'hello'},
        ],
        stream: false,
        extraHeaders: const <String, String>{
          'authorization': 'Bearer extra-attacker-key',
          'X-Trace-Extra': 'trace-extra',
        },
        extraBody: const <String, dynamic>{
          'model': 'extra-attacker-model',
          'stream': false,
          'messages': <dynamic>[],
          'top_p': 0.8,
        },
        client: client,
      ).toList();

      expect(
        captured.url.toString(),
        '${BaiziGateway.baseUrl}/chat/completions',
      );
      expect(captured.headers['authorization'], 'Bearer safe-key');
      expect(captured.headers['x-trace-id'], 'trace-model');
      expect(captured.headers['x-trace-extra'], 'trace-extra');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], modelId);
      expect(body['stream'], isTrue);
      expect(body['messages'], isNotEmpty);
      expect(body['temperature'], 0.2);
      expect(body['top_p'], 0.8);
      expect(chunks.map((chunk) => chunk.content).join(), contains('OK'));
    });

    test('generateText buffers the forced production stream', () async {
      const modelId = 'gpt-5.1';
      late Map<String, dynamic> body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          'data: {"choices":[{"delta":{"content":"streamed "}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"title"},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: <String, String>{'content-type': 'text/event-stream'},
        );
      });

      final result = await ChatApiService.generateText(
        config: _hostileBaiziConfig(modelId),
        modelId: modelId,
        prompt: 'summarize',
        streamClient: client,
      );

      expect(body['stream'], isTrue);
      expect(result, contains('streamed title'));
    });

    test('forces Claude aliases through Anthropic Messages', () async {
      const modelId = 'Vendor/CLAUDE-Sonnet';
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          'data: {"type":"content_block_delta","index":0,'
          '"delta":{"type":"text_delta","text":"Claude"}}\n\n'
          'data: {"type":"message_stop"}\n\n',
          200,
          headers: <String, String>{'content-type': 'text/event-stream'},
        );
      });

      final chunks = await ChatApiService.sendMessageStream(
        config: _hostileBaiziConfig(modelId),
        modelId: modelId,
        messages: const <Map<String, dynamic>>[
          <String, dynamic>{'role': 'system', 'content': 'system prompt'},
          <String, dynamic>{'role': 'user', 'content': 'hello'},
        ],
        stream: false,
        extraHeaders: const <String, String>{'x-api-key': 'extra-attacker-key'},
        extraBody: const <String, dynamic>{
          'model': 'extra-attacker-model',
          'stream': false,
          'messages': <dynamic>[],
        },
        client: client,
      ).toList();

      expect(captured.url.toString(), '${BaiziGateway.baseUrl}/messages');
      expect(captured.headers['x-api-key'], 'safe-key');
      expect(captured.headers['anthropic-version'], '2023-06-01');
      expect(captured.headers.containsKey('authorization'), isFalse);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], modelId);
      expect(body['stream'], isTrue);
      expect(body['system'], 'system prompt');
      expect(body['messages'], isNotEmpty);
      expect(chunks.map((chunk) => chunk.content).join(), contains('Claude'));
    });

    test(
      'redacts failed streaming response bodies for both protocols',
      () async {
        for (final modelId in <String>['gpt-5', 'claude-sonnet']) {
          final client = MockClient((request) async {
            return http.Response(
              '{"apiKey":"response-secret",'
              '"password":"password-secret",'
              '"token":"token-secret",'
              '"secret":"generic-secret",'
              '"privateKey":"private-key-secret",'
              '"credential":"credential-secret",'
              '"client-key":"client-key-secret",'
              '"message":"Bearer echoed-secret"}',
              401,
            );
          });

          await expectLater(
            ChatApiService.sendMessageStream(
              config: _hostileBaiziConfig(modelId),
              modelId: modelId,
              messages: const <Map<String, dynamic>>[
                <String, dynamic>{'role': 'user', 'content': 'hello'},
              ],
              client: client,
            ).toList(),
            throwsA(
              isA<ChatApiHttpException>()
                  .having((error) => error.statusCode, 'status code', 401)
                  .having(
                    (error) {
                      final text = error.toString();
                      return !text.contains('response-secret') &&
                          !text.contains('password-secret') &&
                          !text.contains('token-secret') &&
                          !text.contains('generic-secret') &&
                          !text.contains('private-key-secret') &&
                          !text.contains('credential-secret') &&
                          !text.contains('client-key-secret') &&
                          !text.contains('echoed-secret') &&
                          text.contains(RequestLogger.redactedValue);
                    },
                    'redacted response body',
                    isTrue,
                  ),
            ),
          );
        }
      },
    );
  });
}

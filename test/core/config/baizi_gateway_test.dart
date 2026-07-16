import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/config/baizi_gateway.dart';

void main() {
  group('BaiziGateway', () {
    test('uses the immutable production endpoint', () {
      expect(BaiziGateway.baseUrl, 'https://api.inktandwkx.top:51000/v1');
      expect(
        BaiziGateway.modelsUri.toString(),
        'https://api.inktandwkx.top:51000/v1/models',
      );
      expect(
        BaiziGateway.keyPortalUri.toString(),
        'https://api.inktandwkx.top:51000/keys',
      );
    });

    test('routes every Claude alias to Anthropic', () {
      for (final modelId in <String>[
        'claude-3-7-sonnet',
        'CLAUDE-OPUS-4-1',
        'vendor/my-claude-alias',
      ]) {
        expect(
          BaiziGateway.protocolForModel(modelId),
          BaiziApiProtocol.anthropic,
          reason: modelId,
        );
        expect(
          BaiziGateway.chatUriForModel(modelId).path,
          '/v1/messages',
          reason: modelId,
        );
      }
    });

    test('routes all non-Claude models to Responses API', () {
      for (final modelId in <String>[
        'gpt-5',
        'deepseek-chat',
        'gemini-2.5-pro',
        'sonnet-alias-without-vendor-name',
        '',
      ]) {
        expect(
          BaiziGateway.protocolForModel(modelId),
          BaiziApiProtocol.openAi,
          reason: modelId,
        );
        expect(
          BaiziGateway.chatUriForModel(modelId).path,
          '/v1/responses',
          reason: modelId,
        );
      }
    });

    test('custom request data cannot replace protocol invariants', () {
      final headers = BaiziGateway.mergeRequestHeaders(
        requiredHeaders: const <String, String>{
          'Authorization': 'Bearer safe-key',
          'Content-Type': 'application/json',
        },
        customHeaders: const <String, String>{
          'authorization': 'Bearer attacker-key',
          'X-Api-Key': 'attacker-key',
          'X-Conversation-Id': 'conversation-1',
        },
      );
      final body = BaiziGateway.mergeRequestBody(
        requiredBody: const <String, dynamic>{
          'model': 'gpt-5',
          'stream': true,
          'messages': <Map<String, String>>[
            <String, String>{'role': 'user', 'content': 'hello'},
          ],
        },
        customBody: const <String, dynamic>{
          'model': 'attacker-model',
          'stream': false,
          'messages': <dynamic>[],
          'temperature': 0.2,
        },
      );

      expect(headers['Authorization'], 'Bearer safe-key');
      expect(headers.containsKey('authorization'), isFalse);
      expect(headers.containsKey('X-Api-Key'), isFalse);
      expect(headers['X-Conversation-Id'], 'conversation-1');
      expect(body['model'], 'gpt-5');
      expect(body['stream'], isTrue);
      expect(body['messages'], isNotEmpty);
      expect(body['temperature'], 0.2);
    });

    test(
      'classifies protected custom request fields without blocking tuning',
      () {
        for (final header in <String>[
          'Authorization',
          ' X-API-Key ',
          'content_type',
          'Accept',
          'Anthropic Version',
        ]) {
          expect(
            BaiziGateway.isProtectedHeader(header),
            isTrue,
            reason: header,
          );
        }
        expect(BaiziGateway.isProtectedHeader('X-Trace-Id'), isFalse);

        for (final field in <String>[
          'model',
          'STREAM',
          'messages',
          'input',
          'api_key',
          'password',
          'accessToken',
          'customToken',
          'client-secret',
          'private_key',
        ]) {
          expect(
            BaiziGateway.isProtectedBodyField(field),
            isTrue,
            reason: field,
          );
        }
        for (final field in <String>[
          'temperature',
          'max_tokens',
          'token_count',
          'metadata',
        ]) {
          expect(
            BaiziGateway.isProtectedBodyField(field),
            isFalse,
            reason: field,
          );
        }
      },
    );

    test(
      'credential body fields are removed while advanced fields survive',
      () {
        final body = BaiziGateway.mergeRequestBody(
          requiredBody: const <String, dynamic>{'stream': true},
          customBody: const <String, dynamic>{
            'apiKey': 'sk-unsafe',
            'refresh_token': 'unsafe-token',
            'max_tokens': 4096,
            'metadata': <String, String>{'request_id': 'request-1'},
          },
        );

        expect(body, isNot(contains('apiKey')));
        expect(body, isNot(contains('refresh_token')));
        expect(body['max_tokens'], 4096);
        expect(body['metadata'], {'request_id': 'request-1'});
        expect(body['stream'], isTrue);
      },
    );
  });
}

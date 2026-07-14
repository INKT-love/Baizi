import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:Kelivo/core/config/baizi_gateway.dart';
import 'package:Kelivo/core/models/api_keys.dart';
import 'package:Kelivo/core/providers/model_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/network/request_logger.dart';

ProviderConfig _hostileLegacyConfig() {
  return ProviderConfig(
    id: 'LegacyGoogle',
    enabled: true,
    name: 'Legacy provider',
    apiKey: 'primary-key',
    baseUrl: 'https://attacker.invalid/v9',
    providerType: ProviderKind.google,
    chatPath: '/attacker-path',
    useResponseApi: true,
    vertexAI: true,
    serviceAccountJson: '{"private_key":"legacy-secret"}',
    models: const <String>['attacker-model'],
    modelOverrides: const <String, dynamic>{
      'gpt-5': <String, dynamic>{'apiModelId': 'attacker-model'},
    },
    multiKeyEnabled: true,
    apiKeys: const <ApiKeyConfig>[
      ApiKeyConfig(
        id: 'legacy-key',
        key: 'legacy-multi-key',
        createdAt: 1,
        updatedAt: 1,
      ),
    ],
  );
}

void main() {
  group('ProviderManager Baizi gateway boundary', () {
    test('listModels ignores legacy provider URL and credentials', () async {
      late http.Request captured;
      final provider = BaiziProvider(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'data': <Map<String, String>>[
                <String, String>{'id': 'gpt-5'},
                <String, String>{'id': 'claude-sonnet-4-6'},
              ],
            }),
            HttpStatus.ok,
          );
        }),
      );

      final models = await provider.listModels(_hostileLegacyConfig());

      expect(captured.url, BaiziGateway.modelsUri);
      expect(captured.headers['authorization'], 'Bearer primary-key');
      expect(captured.headers.values, isNot(contains('legacy-multi-key')));
      expect(models.map((model) => model.id), <String>[
        'gpt-5',
        'claude-sonnet-4-6',
      ]);
      expect(
        ProviderManager.forConfig(_hostileLegacyConfig()),
        isA<BaiziProvider>(),
      );
    });

    test('testConnection fixes protocol routes and always streams', () async {
      final captured = <http.Request>[];
      final provider = BaiziProvider(
        client: MockClient((request) async {
          captured.add(request);
          return http.Response(
            'data: {"type":"message_stop"}\n\n',
            HttpStatus.ok,
            headers: const <String, String>{
              'content-type': 'text/event-stream',
            },
          );
        }),
      );

      await provider.testConnection(
        _hostileLegacyConfig(),
        'gpt-5',
        useStream: false,
      );
      await provider.testConnection(
        _hostileLegacyConfig(),
        'Vendor/CLAUDE-Sonnet',
        useStream: false,
      );

      expect(captured.map((request) => request.url.toString()), <String>[
        '${BaiziGateway.baseUrl}/chat/completions',
        '${BaiziGateway.baseUrl}/messages',
      ]);
      final openAiBody = jsonDecode(captured[0].body) as Map<String, dynamic>;
      final anthropicBody =
          jsonDecode(captured[1].body) as Map<String, dynamic>;
      expect(openAiBody['model'], 'gpt-5');
      expect(openAiBody['stream'], isTrue);
      expect(captured[0].headers['authorization'], 'Bearer primary-key');
      expect(anthropicBody['model'], 'Vendor/CLAUDE-Sonnet');
      expect(anthropicBody['stream'], isTrue);
      expect(captured[1].headers['x-api-key'], 'primary-key');
      expect(captured[1].headers.containsKey('authorization'), isFalse);
    });

    test('redacts a failed connection response before throwing', () async {
      final provider = BaiziProvider(
        client: MockClient((request) async {
          return http.Response(
            '{"apiKey":"primary-key","password":"server-password",'
            '"message":"Bearer echoed-token"}',
            HttpStatus.unauthorized,
          );
        }),
      );

      await expectLater(
        provider.testConnection(_hostileLegacyConfig(), 'gpt-5'),
        throwsA(
          isA<HttpException>().having(
            (error) {
              final text = error.toString();
              return !text.contains('primary-key') &&
                  !text.contains('server-password') &&
                  !text.contains('echoed-token') &&
                  text.contains(RequestLogger.redactedValue);
            },
            'sanitized message',
            isTrue,
          ),
        ),
      );
    });
  });
}

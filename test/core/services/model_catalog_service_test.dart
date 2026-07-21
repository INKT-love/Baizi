import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:Baizi/core/config/baizi_gateway.dart';
import 'package:Baizi/core/services/model_catalog_service.dart';

void main() {
  group('ModelCatalogService', () {
    test('fetches every unique model from the fixed Bearer endpoint', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'data': <Map<String, String>>[
              <String, String>{'id': 'gpt-5'},
              <String, String>{'id': 'claude-sonnet-4-5'},
              <String, String>{'id': 'gpt-5'},
              <String, String>{'id': '  deepseek-chat  '},
            ],
          }),
          200,
        );
      });

      final models = await const ModelCatalogService().fetchModels(
        apiKey: ' test-key ',
        client: client,
      );

      expect(captured.url, BaiziGateway.modelsUri);
      expect(captured.headers['Authorization'], 'Bearer test-key');
      expect(models, <String>['gpt-5', 'claude-sonnet-4-5', 'deepseek-chat']);
    });

    test('classifies authentication failures', () async {
      for (final entry in <int, ModelCatalogFailureType>{
        401: ModelCatalogFailureType.unauthorized,
        403: ModelCatalogFailureType.forbidden,
      }.entries) {
        final client = MockClient(
          (_) async => http.Response('denied', entry.key),
        );

        await expectLater(
          const ModelCatalogService().fetchModels(
            apiKey: 'test-key',
            client: client,
          ),
          throwsA(
            isA<ModelCatalogException>().having(
              (error) => error.type,
              'type',
              entry.value,
            ),
          ),
        );
      }
    });

    test('classifies server and malformed response failures', () async {
      final serverClient = MockClient((_) async => http.Response('down', 503));
      final malformedClient = MockClient(
        (_) async => http.Response('{not-json', 200),
      );

      await expectLater(
        const ModelCatalogService().fetchModels(
          apiKey: 'test-key',
          client: serverClient,
        ),
        _failure(ModelCatalogFailureType.server),
      );
      await expectLater(
        const ModelCatalogService().fetchModels(
          apiKey: 'test-key',
          client: malformedClient,
        ),
        _failure(ModelCatalogFailureType.invalidResponse),
      );
    });

    test('rejects empty keys and empty model lists', () async {
      await expectLater(
        const ModelCatalogService().fetchModels(apiKey: ' '),
        _failure(ModelCatalogFailureType.unauthorized),
      );

      final client = MockClient(
        (_) async =>
            http.Response(jsonEncode(<String, Object?>{'data': []}), 200),
      );
      await expectLater(
        const ModelCatalogService().fetchModels(
          apiKey: 'test-key',
          client: client,
        ),
        _failure(ModelCatalogFailureType.empty),
      );
    });

    test('classifies client transport failures', () async {
      final client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );

      await expectLater(
        const ModelCatalogService().fetchModels(
          apiKey: 'test-key',
          client: client,
        ),
        _failure(ModelCatalogFailureType.network),
      );
    });
  });
}

Matcher _failure(ModelCatalogFailureType type) {
  return throwsA(
    isA<ModelCatalogException>().having((error) => error.type, 'type', type),
  );
}

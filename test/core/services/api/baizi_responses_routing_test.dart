import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:Kelivo/core/config/baizi_gateway.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';

void main() {
  test('routes non-Claude Baizi models through Responses API', () async {
    final config = ProviderConfig(
      id: BaiziGateway.providerId,
      enabled: true,
      name: 'Baizi',
      apiKey: 'test-key',
      baseUrl: BaiziGateway.baseUrl,
      providerType: ProviderKind.openai,
      models: const <String>['gpt-5'],
    );
    final client = MockClient((request) async {
      expect(request.url, BaiziGateway.chatUriForModel('gpt-5'));
      expect(request.headers['Authorization'], 'Bearer test-key');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-5');
      expect(body['input'], isA<List>());
      expect(body.containsKey('messages'), isFalse);
      return http.Response(
        'data: {"type":"response.output_text.delta","delta":"ok"}\n\n'
        'data: {"type":"response.completed","response":{"usage":{}}}\n\n',
        200,
        headers: const <String, String>{'content-type': 'text/event-stream'},
      );
    });

    final chunks = await ChatApiService.sendMessageStream(
      config: config,
      modelId: 'gpt-5',
      messages: const <Map<String, String>>[
        <String, String>{'role': 'user', 'content': 'hello'},
      ],
      client: client,
    ).toList();

    expect(chunks.map((chunk) => chunk.content), contains('ok'));
  });
}

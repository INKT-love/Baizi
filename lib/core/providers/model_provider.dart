export '../models/model_types.dart';

import 'dart:convert';
import 'dart:io' show HttpException;
import 'package:http/http.dart' as http;
import '../config/baizi_gateway.dart';
import 'settings_provider.dart';
import '../services/network/dio_http_client.dart';
import '../services/network/request_logger.dart';
import '../services/api_key_manager.dart';
import '../services/api/google_service_account_auth.dart';
import '../models/model_types.dart';

class ModelRegistry {
  // Updated model groups to reflect new series
  // Vision-capable models (text + image input)
  static final RegExp vision = RegExp(
    // GPT family incl. 4o, 4.1, 5 (exclude gpt-5-chat), and OpenAI o* series
    r'(gpt-4o|gpt-4\.1|gpt-5(?!-chat)|o\d|gemini|claude|qwen-?3([-.])5|kimi-k2([-.])(?:5|6|7)|doubao.+1([-.])(?:6|8)|grok-4|step-3|intern-s1|minimax-m3(?:$|[/_:@])|mimo-v2(?:-omni(?:$|[/_:@])|\.5(?:$|[/_:@]))|sensenova-6\.7-flash-lite)',
    caseSensitive: false,
  );
  // Tool-using models
  static final RegExp tool = RegExp(
    (r'(gpt-4o|gpt-4\.1|gpt-oss|gpt-5(?!-chat)|o\d|'
            r'gemini|claude|'
            r'qwen-?3|doubao.+1([-.])(?:6|8)|grok-4|kimi-k2|'
            r'step-3|intern-s1|glm-4([-.])(?:5|6|7)|glm-5|minimax-(?:m2|m3)|'
            r'deepseek-(?:r1|v3|chat|v3\.1|v3\.2|v4)|'
            r'deepseek-reasoner|'
            r'mimo-v2|'
            r'sensenova-6\.7-flash-lite'
            r')')
        .replaceAll(' ', ''),
    caseSensitive: false,
  );
  static final RegExp reasoning = RegExp(
    (r'(gpt-oss|gpt-5(?!-chat)|o\d|'
            r'gemini-(?:2\.5|3).*|gemini-(?:flash-latest|pro-latest)|'
            r'gemini-3-pro-image-preview|'
            r'gemma[-_]?4|'
            r'claude|'
            r'qwen-?3|doubao.+1([-.])(?:6|8)|grok-4|kimi-k2|'
            r'step-3|intern-s1|glm-4([-.])(?:5|6|7)|glm-5|minimax-(?:m2|m3)|'
            r'deepseek-(?:r1|v3\.1|v3\.2|v4)|'
            r'deepseek-reasoner|'
            r'mimo-v2'
            r')')
        .replaceAll(' ', ''),
    caseSensitive: false,
  );

  static bool isLikelyEmbeddingId(String rawId) {
    final id = rawId.toLowerCase();
    return id.contains('embedding') ||
        RegExp(r'(^|[-_/])embed(?:dings?)?([-.]|$)').hasMatch(id);
  }

  static bool _isGemini35Flash(String id) {
    return RegExp(
      r'(^|[/:_-])gemini-3\.5-flash([._:@/-]|$)',
      caseSensitive: false,
    ).hasMatch(id);
  }

  static ModelInfo infer(ModelInfo base) {
    final id = base.id.toLowerCase();
    final inMods = <Modality>[...base.input];
    final outMods = <Modality>[...base.output];
    final ab = <ModelAbility>[...base.abilities];
    final bool inferEmbeddingById = isLikelyEmbeddingId(id);
    if (base.type == ModelType.embedding || inferEmbeddingById) {
      if (!inMods.contains(Modality.text)) inMods.add(Modality.text);
      outMods
        ..clear()
        ..add(Modality.text);
      ab.clear();
      return base.copyWith(
        type: ModelType.embedding,
        input: inMods,
        output: outMods,
        abilities: ab,
      );
    }
    // If model id contains 'image', treat it as an image model:
    // - Input and output both include image
    // - No tool or reasoning abilities
    if (id.contains('image')) {
      if (!inMods.contains(Modality.image)) inMods.add(Modality.image);
      if (!outMods.contains(Modality.image)) outMods.add(Modality.image);
      ab.removeWhere(
        (x) => x == ModelAbility.tool || x == ModelAbility.reasoning,
      );
      return base.copyWith(input: inMods, output: outMods, abilities: ab);
    }
    if (_isGemini35Flash(id)) {
      if (!inMods.contains(Modality.image)) inMods.add(Modality.image);
      outMods
        ..clear()
        ..add(Modality.text);
      if (!ab.contains(ModelAbility.tool)) ab.add(ModelAbility.tool);
      if (!ab.contains(ModelAbility.reasoning)) {
        ab.add(ModelAbility.reasoning);
      }
      return base.copyWith(input: inMods, output: outMods, abilities: ab);
    }
    if (vision.hasMatch(id)) {
      if (!inMods.contains(Modality.image)) inMods.add(Modality.image);
    }
    if (tool.hasMatch(id) && !ab.contains(ModelAbility.tool)) {
      ab.add(ModelAbility.tool);
    }
    if (reasoning.hasMatch(id) && !ab.contains(ModelAbility.reasoning)) {
      ab.add(ModelAbility.reasoning);
    }
    return base.copyWith(input: inMods, output: outMods, abilities: ab);
  }
}

abstract class BaseProvider {
  Future<List<ModelInfo>> listModels(ProviderConfig cfg);
}

class _Http {
  static http.Client clientFor(ProviderConfig cfg) {
    final enabled = cfg.proxyEnabled == true;
    final host = (cfg.proxyHost ?? '').trim();
    final portStr = (cfg.proxyPort ?? '').trim();
    final user = (cfg.proxyUsername ?? '').trim();
    final pass = (cfg.proxyPassword ?? '').trim();
    if (enabled && host.isNotEmpty && portStr.isNotEmpty) {
      final port = int.tryParse(portStr) ?? 8080;
      return DioHttpClient(
        proxy: NetworkProxyConfig(
          enabled: true,
          type: ProviderConfig.resolveProxyType(cfg.proxyType),
          host: host,
          port: port,
          username: user.isEmpty ? null : user,
          password: pass.isEmpty ? null : pass,
        ),
      );
    }
    return DioHttpClient();
  }
}

class OpenAIProvider extends BaseProvider {
  @override
  Future<List<ModelInfo>> listModels(ProviderConfig cfg) async {
    final key = ProviderManager._effectiveApiKey(cfg);
    final client = _Http.clientFor(cfg);
    try {
      final uri = Uri.parse('${cfg.baseUrl}/models');
      final headers = <String, String>{};
      if (key.isNotEmpty) headers['Authorization'] = 'Bearer $key';
      final res = await client.get(uri, headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = (jsonDecode(res.body)['data'] as List?) ?? [];
        return [
          for (final e in data)
            if (e is Map && e['id'] is String)
              ModelRegistry.infer(
                ModelInfo(
                  id: e['id'] as String,
                  displayName: e['id'] as String,
                ),
              ),
        ];
      }
      return [];
    } finally {
      client.close();
    }
  }
}

class ClaudeProvider extends BaseProvider {
  static const String anthropicVersion = '2023-06-01';
  @override
  Future<List<ModelInfo>> listModels(ProviderConfig cfg) async {
    final key = ProviderManager._effectiveApiKey(cfg);
    final client = _Http.clientFor(cfg);
    try {
      final uri = Uri.parse('${cfg.baseUrl}/models');
      final headers = <String, String>{'anthropic-version': anthropicVersion};
      if (key.isNotEmpty) headers['x-api-key'] = key;
      final res = await client.get(uri, headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final obj = jsonDecode(res.body) as Map<String, dynamic>;
        final data = (obj['data'] as List?) ?? [];
        return [
          for (final e in data)
            if (e is Map && e['id'] is String)
              ModelRegistry.infer(
                ModelInfo(
                  id: e['id'] as String,
                  displayName:
                      (e['display_name'] as String?) ?? (e['id'] as String),
                ),
              ),
        ];
      }
      return [];
    } finally {
      client.close();
    }
  }
}

class GoogleProvider extends BaseProvider {
  String _buildUrl(ProviderConfig cfg) {
    if (cfg.vertexAI == true &&
        (cfg.location?.isNotEmpty == true) &&
        (cfg.projectId?.isNotEmpty == true)) {
      final loc = cfg.location!;
      final proj = cfg.projectId!;
      return 'https://aiplatform.googleapis.com/v1/projects/$proj/locations/$loc/publishers/google/models';
    }
    final base = cfg.baseUrl.endsWith('/')
        ? cfg.baseUrl.substring(0, cfg.baseUrl.length - 1)
        : cfg.baseUrl;
    return '$base/models';
  }

  @override
  Future<List<ModelInfo>> listModels(ProviderConfig cfg) async {
    final client = _Http.clientFor(cfg);
    try {
      final url = _buildUrl(cfg);
      final headers = <String, String>{};
      if (cfg.vertexAI == true) {
        final jsonStr = (cfg.serviceAccountJson ?? '').trim();
        if (jsonStr.isNotEmpty) {
          try {
            final token = await GoogleServiceAccountAuth.getAccessTokenFromJson(
              jsonStr,
            );
            headers['Authorization'] = 'Bearer $token';
            final proj = (cfg.projectId ?? '').trim();
            if (proj.isNotEmpty) headers['X-Goog-User-Project'] = proj;
          } catch (_) {}
        } else {
          final key = ProviderManager._effectiveApiKey(cfg);
          if (key.isNotEmpty) {
            // Fallback: treat apiKey as a bearer token if user pasted one
            headers['Authorization'] = 'Bearer $key';
          }
        }
      } else {
        final key = ProviderManager._effectiveApiKey(cfg);
        if (key.isNotEmpty) {
          headers['x-goog-api-key'] = key;
        }
      }
      final out = <ModelInfo>[];
      try {
        final res = await client.get(Uri.parse(url), headers: headers);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final obj = jsonDecode(res.body) as Map<String, dynamic>;
          final arr = (obj['models'] as List?) ?? [];
          for (final e in arr) {
            if (e is Map) {
              final name = (e['name'] as String?) ?? '';
              final id = name.startsWith('models/')
                  ? name.substring('models/'.length)
                  : name;
              final displayName = (e['displayName'] as String?) ?? id;
              final methods =
                  (e['supportedGenerationMethods'] as List?)
                      ?.map((m) => m.toString())
                      .toSet() ??
                  {};
              if (!(methods.contains('generateContent') ||
                  methods.contains('embedContent'))) {
                continue;
              }
              out.add(
                ModelRegistry.infer(
                  ModelInfo(
                    id: id,
                    displayName: displayName,
                    type: methods.contains('generateContent')
                        ? ModelType.chat
                        : ModelType.embedding,
                  ),
                ),
              );
            }
          }
        }
      } catch (_) {}

      // If this is Vertex AI, augment with known Anthropic models
      // Since Google listModels API often only returns Gemini models under publishers/google,
      // we manually inject known supported Claude models for convenience.
      if (cfg.vertexAI == true) {
        final knownClaude = [
          'claude-opus-4-7',
          'claude-opus-4-6',
          'claude-opus-4-5@20251101',
          'claude-opus-4-1@20250805',
          'claude-opus-4@20250514',
          'claude-sonnet-4-6',
          'claude-sonnet-4-5@20250929',
          'claude-sonnet-4@20250514',
          'claude-3-7-sonnet@20250219',
          'claude-3-5-sonnet-v2@20241022',
          'claude-haiku-4-5@20251001',
          'claude-3-5-haiku@20241022',
          'claude-3-5-sonnet@20240620',
          'claude-3-opus@20240229',
          'claude-3-haiku@20240307',
        ];
        for (final id in knownClaude) {
          if (!out.any((m) => m.id == id)) {
            out.add(ModelRegistry.infer(ModelInfo(id: id, displayName: id)));
          }
        }
      }
      return out;
    } finally {
      client.close();
    }
  }
}

class BaiziProvider extends BaseProvider {
  BaiziProvider({this.client});

  final http.Client? client;

  @override
  Future<List<ModelInfo>> listModels(ProviderConfig cfg) async {
    final apiKey = cfg.apiKey.trim();
    if (apiKey.isEmpty) {
      throw const BaiziGatewayException(BaiziGatewayFailureType.missingApiKey);
    }

    final ownsClient = client == null;
    final effectiveClient = client ?? _Http.clientFor(cfg);
    try {
      final response = await effectiveClient.get(
        BaiziGateway.modelsUri,
        headers: <String, String>{
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const <ModelInfo>[];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) {
        return const <ModelInfo>[];
      }
      final seen = <String>{};
      final models = <ModelInfo>[];
      for (final item in decoded['data'] as List) {
        if (item is! Map || item['id'] is! String) continue;
        final id = (item['id'] as String).trim();
        if (id.isEmpty || !seen.add(id)) continue;
        models.add(ModelRegistry.infer(ModelInfo(id: id, displayName: id)));
      }
      return models;
    } finally {
      if (ownsClient) effectiveClient.close();
    }
  }

  Future<void> testConnection(
    ProviderConfig cfg,
    String modelId, {
    bool useStream = false,
  }) async {
    final normalizedModelId = modelId.trim();
    BaiziGateway.validateRequest(
      apiKey: cfg.apiKey,
      availableModels: normalizedModelId.isEmpty
          ? const <String>[]
          : <String>[normalizedModelId],
      modelId: normalizedModelId,
    );

    final protocol = BaiziGateway.protocolForModel(normalizedModelId);
    final body = <String, dynamic>{
      'model': normalizedModelId,
      'messages': const <Map<String, String>>[
        <String, String>{'role': 'user', 'content': 'hello'},
      ],
      'stream': true,
      if (protocol == BaiziApiProtocol.anthropic) 'max_tokens': 8,
    };
    final headers = protocol == BaiziApiProtocol.anthropic
        ? <String, String>{
            'x-api-key': cfg.apiKey.trim(),
            'anthropic-version': ClaudeProvider.anthropicVersion,
            'Content-Type': 'application/json',
          }
        : <String, String>{
            'Authorization': 'Bearer ${cfg.apiKey.trim()}',
            'Content-Type': 'application/json',
          };

    final ownsClient = client == null;
    final effectiveClient = client ?? _Http.clientFor(cfg);
    try {
      final response = await effectiveClient.post(
        BaiziGateway.chatUriForModel(normalizedModelId),
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}: '
          '${RequestLogger.redactBody(response.body)}',
        );
      }
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('text/event-stream') && response.body.isEmpty) {
        throw const HttpException('Stream response expected but not received');
      }
    } finally {
      if (ownsClient) effectiveClient.close();
    }
  }
}

class ProviderManager {
  static String _effectiveApiKey(ProviderConfig cfg) {
    try {
      if (cfg.multiKeyEnabled == true && (cfg.apiKeys?.isNotEmpty == true)) {
        final sel = ApiKeyManager().selectForProvider(cfg);
        if (sel.key != null) return sel.key!.key;
      }
    } catch (_) {}
    return cfg.apiKey;
  }

  static BaseProvider forConfig(ProviderConfig cfg) {
    return BaiziProvider();
  }

  static Future<List<ModelInfo>> listModels(ProviderConfig cfg) {
    return forConfig(cfg).listModels(cfg);
  }

  static Future<void> testConnection(
    ProviderConfig cfg,
    String modelId, {
    bool useStream = false,
  }) async {
    return BaiziProvider().testConnection(cfg, modelId, useStream: useStream);
  }
}

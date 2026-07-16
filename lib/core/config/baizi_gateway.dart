enum BaiziApiProtocol { openAi, anthropic }

enum BaiziGatewayFailureType { missingApiKey, modelUnavailable }

final class BaiziGatewayException implements Exception {
  const BaiziGatewayException(this.type, {this.modelId});

  final BaiziGatewayFailureType type;
  final String? modelId;

  @override
  String toString() => 'BaiziGatewayException(${type.name})';
}

abstract final class BaiziGateway {
  static const String providerId = 'baizi';
  static const String baseUrl = 'https://api.inktandwkx.top:51000/v1';
  static const String keyPortalUrl = 'https://api.inktandwkx.top:51000/keys';

  static const Set<String> _protectedHeaders = <String>{
    'authorization',
    'x-api-key',
    'anthropic-version',
    'content-type',
    'accept',
  };

  static const Set<String> _protectedBodyFields = <String>{
    'model',
    'stream',
    'messages',
    'input',
  };

  static const Set<String> _credentialBodyFields = <String>{
    'authorization',
    'xapikey',
    'token',
    'accesstoken',
    'refreshtoken',
    'authtoken',
    'bearertoken',
    'idtoken',
    'sessiontoken',
    'apitoken',
    'password',
    'passwd',
    'secret',
    'clientsecret',
    'apisecret',
    'secretkey',
    'privatekey',
    'credential',
    'credentials',
  };

  static Uri get modelsUri => Uri.parse('$baseUrl/models');
  static Uri get keyPortalUri => Uri.parse(keyPortalUrl);

  static String _normalizeFieldName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _matchesFieldSet(String value, Set<String> fields) {
    final normalized = _normalizeFieldName(value);
    if (normalized.isEmpty) return false;
    return fields.any((field) => _normalizeFieldName(field) == normalized);
  }

  static bool _isCredentialField(String normalized) {
    return _credentialBodyFields.contains(normalized) ||
        normalized.endsWith('apikey') ||
        normalized.endsWith('password') ||
        normalized.endsWith('token') ||
        normalized.endsWith('clientsecret') ||
        normalized.endsWith('apisecret') ||
        normalized.endsWith('secretkey') ||
        normalized.endsWith('privatekey') ||
        normalized.endsWith('credential') ||
        normalized.endsWith('credentials') ||
        normalized.endsWith('secret');
  }

  static bool isProtectedHeader(String name) {
    final normalized = _normalizeFieldName(name);
    return normalized.isNotEmpty &&
        (_matchesFieldSet(normalized, _protectedHeaders) ||
            _isCredentialField(normalized));
  }

  static bool isProtectedBodyField(String name) {
    final normalized = _normalizeFieldName(name);
    if (normalized.isEmpty) return false;
    if (_matchesFieldSet(normalized, _protectedBodyFields) ||
        _isCredentialField(normalized)) {
      return true;
    }
    return false;
  }

  static BaiziApiProtocol protocolForModel(String modelId) {
    return modelId.trim().toLowerCase().contains('claude')
        ? BaiziApiProtocol.anthropic
        : BaiziApiProtocol.openAi;
  }

  static Uri chatUriForModel(String modelId) {
    final path = switch (protocolForModel(modelId)) {
      BaiziApiProtocol.openAi => '/responses',
      BaiziApiProtocol.anthropic => '/messages',
    };
    return Uri.parse('$baseUrl$path');
  }

  static void validateRequest({
    required String apiKey,
    required Iterable<String> availableModels,
    required String modelId,
  }) {
    if (apiKey.trim().isEmpty) {
      throw const BaiziGatewayException(BaiziGatewayFailureType.missingApiKey);
    }
    if (!availableModels.contains(modelId)) {
      throw BaiziGatewayException(
        BaiziGatewayFailureType.modelUnavailable,
        modelId: modelId,
      );
    }
  }

  static Map<String, String> mergeRequestHeaders({
    required Map<String, String> requiredHeaders,
    Map<String, String>? customHeaders,
  }) {
    final merged = <String, String>{};
    for (final entry in (customHeaders ?? const <String, String>{}).entries) {
      if (isProtectedHeader(entry.key)) continue;
      merged[entry.key] = entry.value;
    }
    merged.addAll(requiredHeaders);
    return merged;
  }

  static Map<String, dynamic> mergeRequestBody({
    required Map<String, dynamic> requiredBody,
    Map<String, dynamic>? customBody,
  }) {
    final merged = <String, dynamic>{};
    for (final entry in (customBody ?? const <String, dynamic>{}).entries) {
      if (isProtectedBodyField(entry.key)) {
        continue;
      }
      merged[entry.key] = entry.value;
    }
    merged.addAll(requiredBody);
    return merged;
  }
}

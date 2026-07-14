import 'dart:convert';

import '../../config/baizi_gateway.dart';
import '../network/request_logger.dart';

abstract final class BackupDataSanitizer {
  static const Set<String> _credentialListPreferenceKeys = <String>{
    'search_services_v1',
    'tts_services_v1',
    'mcp_servers_v1',
  };
  static const Set<String> _credentialMapPreferenceKeys = <String>{
    'webdav_config_v1',
    's3_config_v1',
  };
  static const Set<String> _credentialFieldNames = <String>{
    'authorization',
    'proxyauthorization',
    'xapikey',
    'apikey',
    'accesskey',
    'accesskeyid',
    'secretaccesskey',
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
    'clientkey',
    'cookie',
    'setcookie',
  };
  static const Set<String> _excludedPreferenceKeys = <String>{
    'provider_configs_v1',
    'provider_configs_backup_v1',
    'providers_order_v1',
    'provider_groups_v1',
    'provider_group_map_v1',
    'provider_group_collapsed_v1',
    'provider_ungrouped_position_v1',
  };

  static bool canSyncPreference(String key) {
    if (_excludedPreferenceKeys.contains(key)) return false;

    return !_isSensitivePreferenceKey(key);
  }

  static Map<String, dynamic> filterSyncPreferences(
    Map<String, dynamic> preferences,
  ) {
    return <String, dynamic>{
      for (final entry in preferences.entries)
        if (canSyncPreference(entry.key)) entry.key: entry.value,
    };
  }

  static Map<String, dynamic> sanitizePreferences(
    Map<String, dynamic> preferences,
  ) {
    return <String, dynamic>{
      for (final entry in filterSyncPreferences(preferences).entries)
        entry.key: sanitizePreferenceValue(entry.key, entry.value),
    };
  }

  static dynamic sanitizePreferenceValue(String key, dynamic value) {
    if (_credentialListPreferenceKeys.contains(key)) {
      return _sanitizeCredentialJson(key, value, expectsList: true);
    }
    if (_credentialMapPreferenceKeys.contains(key)) {
      return _sanitizeCredentialJson(key, value, expectsList: false);
    }
    if (key != 'assistants_v1' || value is! String) return value;

    try {
      final assistants = jsonDecode(value);
      if (assistants is! List || assistants.any((item) => item is! Map)) {
        return jsonEncode(const <dynamic>[]);
      }
      return jsonEncode(<dynamic>[
        for (final assistant in assistants)
          _sanitizeAssistant(assistant as Map),
      ]);
    } catch (_) {
      return jsonEncode(const <dynamic>[]);
    }
  }

  static dynamic mergePreferenceForRestore(
    String key,
    dynamic incomingValue,
    dynamic existingValue,
  ) {
    final sanitized = sanitizePreferenceValue(key, incomingValue);
    if (sanitized is! String ||
        (!_credentialListPreferenceKeys.contains(key) &&
            !_credentialMapPreferenceKeys.contains(key))) {
      return sanitized;
    }

    try {
      final incoming = jsonDecode(sanitized);
      final existing = existingValue is String
          ? jsonDecode(existingValue)
          : null;
      if (_credentialListPreferenceKeys.contains(key)) {
        if (incoming is! List) return '[]';
        final existingById = <String, Map<String, dynamic>>{};
        if (existing is List) {
          for (final item in existing) {
            if (item is! Map) continue;
            final map = _stringKeyedMap(item);
            final id = map['id']?.toString().trim() ?? '';
            if (id.isNotEmpty) existingById[id] = map;
          }
        }

        final restored = <Map<String, dynamic>>[];
        final rawMcpEntries = key == 'mcp_servers_v1'
            ? _rawMcpEntriesById(incomingValue)
            : const <String, Map<String, dynamic>>{};
        for (final item in incoming) {
          if (item is! Map) continue;
          var map = _stringKeyedMap(item);
          final id = map['id']?.toString().trim() ?? '';
          final local = id.isEmpty ? null : existingById[id];
          final canRestoreMcpContainers =
              key != 'mcp_servers_v1' ||
              _canRestoreMcpContainers(rawMcpEntries[id], map, local);
          if (local != null &&
              _hasSameCredentialTarget(key, map, local) &&
              canRestoreMcpContainers) {
            map = _restoreCredentials(map, local);
            if (key == 'mcp_servers_v1') {
              map = _restoreMcpContainers(map, local);
            }
          }
          if (key == 'search_services_v1') {
            map.putIfAbsent('apiKey', () => '');
          }
          restored.add(map);
        }
        return jsonEncode(restored);
      }

      if (incoming is! Map) return '{}';
      var restored = _stringKeyedMap(incoming);
      if (existing is Map) {
        final local = _stringKeyedMap(existing);
        if (_hasSameCredentialTarget(key, restored, local)) {
          restored = _restoreCredentials(restored, local);
        }
      }
      return jsonEncode(restored);
    } catch (_) {
      return _credentialListPreferenceKeys.contains(key) ? '[]' : '{}';
    }
  }

  static String _sanitizeCredentialJson(
    String key,
    dynamic value, {
    required bool expectsList,
  }) {
    final failClosed = expectsList ? '[]' : '{}';
    if (value is! String) return failClosed;
    try {
      final decoded = jsonDecode(value);
      if (expectsList) {
        if (decoded is! List) return failClosed;
        return jsonEncode(<dynamic>[
          for (final item in decoded)
            if (item is Map)
              key == 'mcp_servers_v1'
                  ? _sanitizeMcpServerNode(item)
                  : _sanitizeCredentialNode(item),
        ]);
      }
      if (decoded is! Map) return failClosed;
      return jsonEncode(_sanitizeCredentialNode(decoded));
    } catch (_) {
      return failClosed;
    }
  }

  static dynamic _sanitizeCredentialNode(dynamic value) {
    if (value is Map) {
      final sanitized = <String, dynamic>{};
      for (final entry in value.entries) {
        final fieldName = entry.key.toString();
        if (_isCredentialField(fieldName)) continue;
        sanitized[fieldName] = _sanitizeCredentialNode(entry.value);
      }
      return sanitized;
    }
    if (value is List) {
      return <dynamic>[for (final item in value) _sanitizeCredentialNode(item)];
    }
    return value;
  }

  static Map<String, dynamic> _sanitizeMcpServerNode(
    Map<dynamic, dynamic> raw,
  ) {
    final sanitized = <String, dynamic>{};
    for (final entry in raw.entries) {
      final fieldName = entry.key.toString();
      final normalized = fieldName.toLowerCase().replaceAll(
        RegExp('[^a-z0-9]'),
        '',
      );
      if (normalized == 'headers' ||
          normalized == 'env' ||
          _isCredentialField(fieldName)) {
        continue;
      }
      sanitized[fieldName] = _sanitizeCredentialNode(entry.value);
    }
    return sanitized;
  }

  static Map<String, dynamic> _restoreCredentials(
    Map<String, dynamic> incoming,
    Map<String, dynamic> existing,
  ) {
    final restored = _stringKeyedMap(incoming);
    for (final entry in existing.entries) {
      final fieldName = entry.key;
      final existingField = entry.value;
      if (_isCredentialField(fieldName)) {
        if (_hasCredentialValue(existingField)) {
          restored[fieldName] = existingField;
        }
        continue;
      }

      final incomingField = restored[fieldName];
      if (incomingField is Map && existingField is Map) {
        restored[fieldName] = _restoreCredentials(
          _stringKeyedMap(incomingField),
          _stringKeyedMap(existingField),
        );
      }
    }
    return restored;
  }

  static Map<String, dynamic> _restoreMcpContainers(
    Map<String, dynamic> incoming,
    Map<String, dynamic> existing,
  ) {
    final restored = _stringKeyedMap(incoming);
    for (final entry in existing.entries) {
      final normalized = entry.key.toLowerCase().replaceAll(
        RegExp('[^a-z0-9]'),
        '',
      );
      if (normalized == 'headers' || normalized == 'env') {
        restored[entry.key] = entry.value;
      }
    }
    return restored;
  }

  static Map<String, Map<String, dynamic>> _rawMcpEntriesById(dynamic value) {
    if (value is! String) return const <String, Map<String, dynamic>>{};
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const <String, Map<String, dynamic>>{};
      return <String, Map<String, dynamic>>{
        for (final item in decoded)
          if (item is Map &&
              (item['id']?.toString().trim().isNotEmpty ?? false))
            item['id'].toString().trim(): _stringKeyedMap(item),
      };
    } catch (_) {
      return const <String, Map<String, dynamic>>{};
    }
  }

  static bool _canRestoreMcpContainers(
    Map<String, dynamic>? rawIncoming,
    Map<String, dynamic> sanitizedIncoming,
    Map<String, dynamic>? existing,
  ) {
    if (rawIncoming == null || existing == null) return false;
    for (final key in rawIncoming.keys) {
      final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
      if (normalized == 'headers' || normalized == 'env') return false;
    }
    return _hasSameCredentialTarget(
      'mcp_servers_v1',
      sanitizedIncoming,
      existing,
    );
  }

  static bool _hasCredentialValue(dynamic value) {
    if (value == null) return false;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized.isNotEmpty &&
          normalized != '<redacted>' &&
          normalized != 'redacted' &&
          normalized != '***';
    }
    if (value is Map || value is Iterable) return value.isNotEmpty;
    return true;
  }

  static bool _hasSameCredentialTarget(
    String key,
    Map<String, dynamic> incoming,
    Map<String, dynamic> existing,
  ) {
    switch (key) {
      case 'search_services_v1':
        return _targetFieldsMatch(incoming, existing, const <String>[
          'type',
          'url',
          'baseUrl',
          'customUrl',
          'endpoint',
          'host',
        ]);
      case 'tts_services_v1':
        return _targetFieldsMatch(incoming, existing, const <String>[
          'kind',
          'baseUrl',
        ]);
      case 'mcp_servers_v1':
        final transport = incoming['transport']?.toString().trim() ?? '';
        if (!_targetFieldsMatch(incoming, existing, const <String>[
          'transport',
        ])) {
          return false;
        }
        return transport == 'stdio'
            ? _targetFieldsMatch(incoming, existing, const <String>[
                'command',
                'args',
                'workingDirectory',
              ])
            : _routingUrlsMatch(incoming['url'], existing['url']);
      case 'webdav_config_v1':
        return _targetFieldsMatch(incoming, existing, const <String>[
              'url',
              'username',
            ]) &&
            _normalizeWebDavPath(incoming['path']) ==
                _normalizeWebDavPath(existing['path']);
      case 's3_config_v1':
        return _targetFieldsMatch(incoming, existing, const <String>[
              'endpoint',
              'bucket',
            ]) &&
            _normalizeS3Region(incoming['region']) ==
                _normalizeS3Region(existing['region']) &&
            _normalizeS3Prefix(incoming['prefix']) ==
                _normalizeS3Prefix(existing['prefix']) &&
            _normalizeS3PathStyle(incoming['pathStyle']) ==
                _normalizeS3PathStyle(existing['pathStyle']);
      default:
        return false;
    }
  }

  static bool _targetFieldsMatch(
    Map<String, dynamic> incoming,
    Map<String, dynamic> existing,
    List<String> fields,
  ) {
    for (final field in fields) {
      if (_normalizeTargetValue(incoming[field]) !=
          _normalizeTargetValue(existing[field])) {
        return false;
      }
    }
    return true;
  }

  static String _normalizeTargetValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    return jsonEncode(value);
  }

  static String _normalizeS3Region(dynamic value) {
    if (value == null) return 'us-east-1';
    final normalized = value.toString().trim();
    return normalized.isEmpty ? 'us-east-1' : normalized;
  }

  static String _normalizeWebDavPath(dynamic value) {
    if (value == null) return 'kelivo_backups';
    final normalized = value.toString().trim();
    return normalized.isEmpty ? 'kelivo_backups' : normalized;
  }

  static String _normalizeS3Prefix(dynamic value) {
    if (value == null) return 'kelivo_backups';
    final normalized = value.toString().trim();
    return normalized.isEmpty ? 'kelivo_backups' : normalized;
  }

  static bool _routingUrlsMatch(dynamic incoming, dynamic existing) {
    return _normalizeRoutingUrl(incoming) == _normalizeRoutingUrl(existing);
  }

  static String _normalizeRoutingUrl(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return raw;
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final userInfo = uri.userInfo;
    final port = uri.hasPort ? ':${uri.port}' : '';
    final authority = userInfo.isEmpty ? '$host$port' : '$userInfo@$host$port';
    final path = uri.path.isEmpty ? '' : uri.path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '$scheme://$authority$path$query';
  }

  static String _normalizeS3PathStyle(dynamic value) {
    if (value == null) return 'true';
    if (value is bool) return value ? 'true' : 'false';
    final normalized = value.toString().trim().toLowerCase();
    return normalized.isEmpty ? 'true' : normalized;
  }

  static Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> value) {
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }

  static bool _isCredentialField(String fieldName) {
    final normalized = fieldName.toLowerCase().replaceAll(
      RegExp('[^a-z0-9]'),
      '',
    );
    if (normalized.isEmpty) return false;
    return _credentialFieldNames.contains(normalized) ||
        normalized.endsWith('apikey') ||
        normalized.endsWith('password') ||
        normalized.endsWith('token') ||
        normalized.endsWith('clientsecret') ||
        normalized.endsWith('apisecret') ||
        normalized.endsWith('secretkey') ||
        normalized.endsWith('privatekey') ||
        normalized.endsWith('credential') ||
        normalized.endsWith('credentials') ||
        normalized.endsWith('clientkey') ||
        normalized.endsWith('accesskey') ||
        normalized.endsWith('accesskeyid') ||
        normalized.endsWith('secret');
  }

  static bool _isSensitivePreferenceKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    final stem = normalized.replaceFirst(RegExp(r'v\d+$'), '');
    final raw = key.trim();
    return _isCredentialField(stem) ||
        stem.startsWith('apikey') ||
        stem.startsWith('apitoken') ||
        stem.startsWith('sessiontoken') ||
        stem.startsWith('authorization') ||
        stem.startsWith('cookie') ||
        stem.startsWith('accesskey') ||
        stem.startsWith('privatekey') ||
        stem.startsWith('credential') ||
        stem.startsWith('providerkey') ||
        stem.startsWith('clientsecret') ||
        stem.startsWith('serviceaccount') ||
        stem.startsWith('password') ||
        stem.startsWith('baseurl') ||
        stem.startsWith('apihost') ||
        stem.startsWith('apiendpoint') ||
        RegExp(r'^secret(?:[^A-Za-z0-9]|[A-Z])').hasMatch(raw);
  }

  static Map<String, dynamic> _sanitizeAssistant(Map<dynamic, dynamic> raw) {
    final assistant = _stringKeyedMap(_sanitizeCredentialNode(raw) as Map);
    assistant['chatModelProvider'] = BaiziGateway.providerId;

    if (assistant.containsKey('customHeaders')) {
      assistant['customHeaders'] = _sanitizeCustomEntries(
        assistant['customHeaders'],
        keyNames: const <String>['name', 'key'],
        isProtected: BaiziGateway.isProtectedHeader,
      );
    }
    if (assistant.containsKey('customBody')) {
      assistant['customBody'] = _sanitizeCustomEntries(
        assistant['customBody'],
        keyNames: const <String>['key', 'name'],
        isProtected: BaiziGateway.isProtectedBodyField,
      );
    }
    return assistant;
  }

  static List<Map<String, dynamic>> _sanitizeCustomEntries(
    dynamic raw, {
    required List<String> keyNames,
    required bool Function(String value) isProtected,
  }) {
    if (raw is! List) return const <Map<String, dynamic>>[];

    final sanitized = <Map<String, dynamic>>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = <String, dynamic>{
        for (final item in entry.entries) item.key.toString(): item.value,
      };
      final fieldName = keyNames
          .map((name) => map[name]?.toString() ?? '')
          .firstWhere((name) => name.trim().isNotEmpty, orElse: () => '');
      if (fieldName.trim().isEmpty ||
          isProtected(fieldName) ||
          _containsCredentialSemantic(fieldName)) {
        continue;
      }
      if (map.containsKey('value')) {
        map['value'] = _sanitizeCustomEntryValue(map['value']);
      }
      sanitized.add(map);
    }
    return sanitized;
  }

  static bool _containsCredentialSemantic(String fieldName) {
    final normalized = fieldName.toLowerCase().replaceAll(
      RegExp('[^a-z0-9]'),
      '',
    );
    if (normalized.isEmpty) return false;
    return _isCredentialField(fieldName) ||
        normalized.contains('authorization') ||
        normalized.contains('apikey') ||
        normalized.contains('accesskey') ||
        normalized.contains('token') ||
        normalized.contains('password') ||
        normalized.contains('secret') ||
        normalized.contains('privatekey') ||
        normalized.contains('credential') ||
        normalized.contains('clientkey');
  }

  static dynamic _sanitizeCustomEntryValue(dynamic value) {
    if (value is String) {
      try {
        return jsonEncode(_sanitizeCredentialNode(jsonDecode(value)));
      } catch (_) {
        return RequestLogger.redactText(value);
      }
    }
    return _sanitizeCredentialNode(value);
  }
}

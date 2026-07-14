class AssistantCharacterData {
  AssistantCharacterData({
    this.cardVersion = '',
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    this.firstMes = '',
    List<String> alternateGreetings = const <String>[],
    this.mesExample = '',
    List<String> cardTags = const <String>[],
    this.cardWorldBookId,
    String? sourceFileName,
    Map<String, dynamic> extensions = const <String, dynamic>{},
    Map<String, dynamic> unknownFields = const <String, dynamic>{},
  }) : alternateGreetings = List<String>.unmodifiable(alternateGreetings),
       cardTags = List<String>.unmodifiable(cardTags),
       sourceFileName = _validateSourceFileName(sourceFileName),
       extensions = _freezeJsonMap(extensions),
       unknownFields = _freezeJsonMap(unknownFields);

  final String cardVersion;
  final String description;
  final String personality;
  final String scenario;
  final String systemPrompt;
  final String postHistoryInstructions;
  final String firstMes;
  final List<String> alternateGreetings;
  final String mesExample;
  final List<String> cardTags;
  final String? cardWorldBookId;

  /// Path relative to the app-managed character_cards directory.
  final String? sourceFileName;

  final Map<String, dynamic> extensions;
  final Map<String, dynamic> unknownFields;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'cardVersion': cardVersion,
    'description': description,
    'personality': personality,
    'scenario': scenario,
    'systemPrompt': systemPrompt,
    'postHistoryInstructions': postHistoryInstructions,
    'firstMes': firstMes,
    'alternateGreetings': List<String>.from(alternateGreetings),
    'mesExample': mesExample,
    'cardTags': List<String>.from(cardTags),
    'cardWorldBookId': cardWorldBookId,
    'sourceFileName': sourceFileName,
    'extensions': _copyJsonMap(extensions),
    'unknownFields': _copyJsonMap(unknownFields),
  };

  factory AssistantCharacterData.fromJson(Map<String, dynamic> json) {
    return AssistantCharacterData(
      cardVersion: _stringOrEmpty(json['cardVersion']),
      description: _stringOrEmpty(json['description']),
      personality: _stringOrEmpty(json['personality']),
      scenario: _stringOrEmpty(json['scenario']),
      systemPrompt: _stringOrEmpty(json['systemPrompt']),
      postHistoryInstructions: _stringOrEmpty(json['postHistoryInstructions']),
      firstMes: _stringOrEmpty(json['firstMes']),
      alternateGreetings: _stringList(json['alternateGreetings']),
      mesExample: _stringOrEmpty(json['mesExample']),
      cardTags: _stringList(json['cardTags']),
      cardWorldBookId: _nullableString(json['cardWorldBookId']),
      sourceFileName: _safeSourceFileName(json['sourceFileName']),
      extensions: _mapOrEmpty(json['extensions']),
      unknownFields: _mapOrEmpty(json['unknownFields']),
    );
  }
}

String _stringOrEmpty(Object? value) => value is String ? value : '';

String? _nullableString(Object? value) => value is String ? value : null;

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList(growable: false);
}

Map<String, dynamic> _mapOrEmpty(Object? value) {
  if (value is! Map) return const <String, dynamic>{};
  return <String, dynamic>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

String? _safeSourceFileName(Object? value) {
  if (value is! String) return null;
  try {
    return _validateSourceFileName(value);
  } on ArgumentError {
    return null;
  }
}

String? _validateSourceFileName(String? value) {
  if (value == null) return null;
  if (value.isEmpty || value.contains('\u0000')) {
    throw ArgumentError.value(value, 'sourceFileName', 'Invalid relative path');
  }

  final normalized = value.replaceAll('\\', '/');
  final hasUriScheme = RegExp(
    r'^[A-Za-z][A-Za-z0-9+.-]*:',
  ).hasMatch(normalized);
  final segments = normalized.split('/');
  if (normalized.startsWith('/') ||
      hasUriScheme ||
      segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..',
      )) {
    throw ArgumentError.value(value, 'sourceFileName', 'Invalid relative path');
  }
  return normalized;
}

Map<String, dynamic> _freezeJsonMap(Map<String, dynamic> source) {
  return Map<String, dynamic>.unmodifiable(<String, dynamic>{
    for (final entry in source.entries)
      entry.key: _freezeJsonValue(entry.value),
  });
}

dynamic _freezeJsonValue(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(<String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _freezeJsonValue(entry.value),
    });
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(value.map(_freezeJsonValue));
  }
  if (value == null || value is String || value is bool) return value;
  if (value is num && value.isFinite) return value;
  throw ArgumentError.value(
    value,
    'value',
    'Only JSON-compatible values can be persisted',
  );
}

Map<String, dynamic> _copyJsonMap(Map<String, dynamic> source) {
  return <String, dynamic>{
    for (final entry in source.entries) entry.key: _copyJsonValue(entry.value),
  };
}

dynamic _copyJsonValue(dynamic value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _copyJsonValue(entry.value),
    };
  }
  if (value is List) {
    return value.map(_copyJsonValue).toList(growable: false);
  }
  return value;
}

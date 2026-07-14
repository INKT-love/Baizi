enum CharacterCardSpec { v1, v2, v3 }

enum CharacterCardParseErrorCode {
  fileTooLarge,
  jsonTooLarge,
  jsonTooDeep,
  jsonTooManyNodes,
  invalidJson,
  invalidUtf8,
  invalidCard,
  invalidField,
  unsupportedSpec,
  invalidPngSignature,
  invalidPngStructure,
  truncatedPng,
  invalidPngCrc,
  invalidPngPixels,
  pngDimensionsTooLarge,
  pngMetadataTooLarge,
  decompressedDataTooLarge,
  missingPngMetadata,
  conflictingPngMetadata,
  invalidBase64,
}

class CharacterCardParseException implements Exception {
  const CharacterCardParseException(this.code, this.message);

  final CharacterCardParseErrorCode code;
  final String message;

  @override
  String toString() => 'CharacterCardParseException(${code.name}): $message';
}

class CharacterCardLimits {
  const CharacterCardLimits({
    this.maxFileBytes = 32 * 1024 * 1024,
    this.maxMetadataChunkBytes = 8 * 1024 * 1024,
    this.maxJsonBytes = 16 * 1024 * 1024,
    this.maxJsonDepth = 64,
    this.maxJsonNodes = 100000,
  });

  static const CharacterCardLimits defaults = CharacterCardLimits();

  final int maxFileBytes;
  final int maxMetadataChunkBytes;
  final int maxJsonBytes;
  final int maxJsonDepth;
  final int maxJsonNodes;

  int get maxBase64Bytes => ((maxJsonBytes + 2) ~/ 3) * 4;

  CharacterCardLimits copyWith({
    int? maxFileBytes,
    int? maxMetadataChunkBytes,
    int? maxJsonBytes,
    int? maxJsonDepth,
    int? maxJsonNodes,
  }) {
    return CharacterCardLimits(
      maxFileBytes: maxFileBytes ?? this.maxFileBytes,
      maxMetadataChunkBytes:
          maxMetadataChunkBytes ?? this.maxMetadataChunkBytes,
      maxJsonBytes: maxJsonBytes ?? this.maxJsonBytes,
      maxJsonDepth: maxJsonDepth ?? this.maxJsonDepth,
      maxJsonNodes: maxJsonNodes ?? this.maxJsonNodes,
    );
  }
}

class CharacterCardDocument {
  CharacterCardDocument({
    required this.spec,
    required this.specVersion,
    required this.data,
    Map<String, dynamic> unknownFields = const <String, dynamic>{},
  }) : unknownFields = Map.unmodifiable(_copyJsonMap(unknownFields));

  final CharacterCardSpec spec;
  final String specVersion;
  final CharacterCardData data;
  final Map<String, dynamic> unknownFields;

  Map<String, dynamic> toJson() {
    if (spec == CharacterCardSpec.v1) {
      return <String, dynamic>{
        ..._copyJsonMap(unknownFields),
        'name': data.name,
        'description': data.description,
        'personality': data.personality,
        'scenario': data.scenario,
        'first_mes': data.firstMes,
        'mes_example': data.mesExample,
      };
    }

    return <String, dynamic>{
      ..._copyJsonMap(unknownFields),
      'spec': spec == CharacterCardSpec.v2 ? 'chara_card_v2' : 'chara_card_v3',
      'spec_version': specVersion,
      'data': data.toJson(spec),
    };
  }
}

class CharacterCardData {
  CharacterCardData({
    this.name = '',
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.firstMes = '',
    this.mesExample = '',
    this.creatorNotes = '',
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    List<String> alternateGreetings = const <String>[],
    this.characterBook,
    List<String> tags = const <String>[],
    this.creator = '',
    this.characterVersion = '',
    Map<String, dynamic> extensions = const <String, dynamic>{},
    List<CharacterCardAsset> assets = const <CharacterCardAsset>[],
    this.nickname,
    Map<String, String> creatorNotesMultilingual = const <String, String>{},
    List<String> source = const <String>[],
    List<String> groupOnlyGreetings = const <String>[],
    this.creationDate,
    this.modificationDate,
    Map<String, dynamic> unknownFields = const <String, dynamic>{},
  }) : alternateGreetings = List.unmodifiable(alternateGreetings),
       tags = List.unmodifiable(tags),
       extensions = Map.unmodifiable(_copyJsonMap(extensions)),
       assets = List.unmodifiable(assets),
       creatorNotesMultilingual = Map.unmodifiable(creatorNotesMultilingual),
       source = List.unmodifiable(source),
       groupOnlyGreetings = List.unmodifiable(groupOnlyGreetings),
       unknownFields = Map.unmodifiable(_copyJsonMap(unknownFields));

  final String name;
  final String description;
  final String personality;
  final String scenario;
  final String firstMes;
  final String mesExample;
  final String creatorNotes;
  final String systemPrompt;
  final String postHistoryInstructions;
  final List<String> alternateGreetings;
  final CharacterBookData? characterBook;
  final List<String> tags;
  final String creator;
  final String characterVersion;
  final Map<String, dynamic> extensions;
  final List<CharacterCardAsset> assets;
  final String? nickname;
  final Map<String, String> creatorNotesMultilingual;
  final List<String> source;
  final List<String> groupOnlyGreetings;
  final int? creationDate;
  final int? modificationDate;
  final Map<String, dynamic> unknownFields;

  Map<String, dynamic> toJson(CharacterCardSpec spec) {
    final result = <String, dynamic>{
      ..._copyJsonMap(unknownFields),
      'name': name,
      'description': description,
      'personality': personality,
      'scenario': scenario,
      'first_mes': firstMes,
      'mes_example': mesExample,
      'creator_notes': creatorNotes,
      'system_prompt': systemPrompt,
      'post_history_instructions': postHistoryInstructions,
      'alternate_greetings': List<String>.from(alternateGreetings),
      if (characterBook != null) 'character_book': characterBook!.toJson(spec),
      'tags': List<String>.from(tags),
      'creator': creator,
      'character_version': characterVersion,
      'extensions': _copyJsonMap(extensions),
    };

    if (spec == CharacterCardSpec.v3) {
      if (assets.isNotEmpty) {
        result['assets'] = assets.map((asset) => asset.toJson()).toList();
      }
      if (nickname != null) result['nickname'] = nickname;
      if (creatorNotesMultilingual.isNotEmpty) {
        result['creator_notes_multilingual'] = Map<String, String>.from(
          creatorNotesMultilingual,
        );
      }
      if (source.isNotEmpty) result['source'] = List<String>.from(source);
      result['group_only_greetings'] = List<String>.from(groupOnlyGreetings);
      if (creationDate != null) result['creation_date'] = creationDate;
      if (modificationDate != null) {
        result['modification_date'] = modificationDate;
      }
    }

    return result;
  }
}

class CharacterCardAsset {
  CharacterCardAsset({
    required this.type,
    required this.uri,
    required this.name,
    required this.ext,
    Map<String, dynamic> unknownFields = const <String, dynamic>{},
  }) : unknownFields = Map.unmodifiable(_copyJsonMap(unknownFields));

  final String type;
  final String uri;
  final String name;
  final String ext;
  final Map<String, dynamic> unknownFields;

  Map<String, dynamic> toJson() => <String, dynamic>{
    ..._copyJsonMap(unknownFields),
    'type': type,
    'uri': uri,
    'name': name,
    'ext': ext,
  };
}

class CharacterBookData {
  CharacterBookData({
    this.name,
    this.description,
    this.scanDepth,
    this.tokenBudget,
    this.recursiveScanning,
    Map<String, dynamic> extensions = const <String, dynamic>{},
    List<CharacterBookEntryData> entries = const <CharacterBookEntryData>[],
    Map<String, dynamic> unknownFields = const <String, dynamic>{},
  }) : extensions = Map.unmodifiable(_copyJsonMap(extensions)),
       entries = List.unmodifiable(entries),
       unknownFields = Map.unmodifiable(_copyJsonMap(unknownFields));

  final String? name;
  final String? description;
  final int? scanDepth;
  final int? tokenBudget;
  final bool? recursiveScanning;
  final Map<String, dynamic> extensions;
  final List<CharacterBookEntryData> entries;
  final Map<String, dynamic> unknownFields;

  Map<String, dynamic> toJson(CharacterCardSpec spec) => <String, dynamic>{
    ..._copyJsonMap(unknownFields),
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    if (scanDepth != null) 'scan_depth': scanDepth,
    if (tokenBudget != null) 'token_budget': tokenBudget,
    if (recursiveScanning != null) 'recursive_scanning': recursiveScanning,
    'extensions': _copyJsonMap(extensions),
    'entries': entries.map((entry) => entry.toJson(spec)).toList(),
  };
}

class CharacterBookEntryData {
  CharacterBookEntryData({
    List<String> keys = const <String>[],
    this.content = '',
    Map<String, dynamic> extensions = const <String, dynamic>{},
    this.enabled = true,
    this.insertionOrder = 0,
    this.caseSensitive,
    this.useRegex = false,
    this.name,
    this.priority,
    this.sourceId,
    this.comment,
    this.selective,
    List<String> secondaryKeys = const <String>[],
    this.constant,
    this.position,
    Map<String, dynamic> unknownFields = const <String, dynamic>{},
  }) : keys = List.unmodifiable(keys),
       extensions = Map.unmodifiable(_copyJsonMap(extensions)),
       secondaryKeys = List.unmodifiable(secondaryKeys),
       unknownFields = Map.unmodifiable(_copyJsonMap(unknownFields));

  final List<String> keys;
  final String content;
  final Map<String, dynamic> extensions;
  final bool enabled;
  final int insertionOrder;
  final bool? caseSensitive;
  final bool useRegex;
  final String? name;
  final int? priority;
  final Object? sourceId;
  final String? comment;
  final bool? selective;
  final List<String> secondaryKeys;
  final bool? constant;
  final String? position;
  final Map<String, dynamic> unknownFields;

  Map<String, dynamic> toJson(CharacterCardSpec spec) => <String, dynamic>{
    ..._copyJsonMap(unknownFields),
    'keys': List<String>.from(keys),
    'content': content,
    'extensions': _copyJsonMap(extensions),
    'enabled': enabled,
    'insertion_order': insertionOrder,
    if (caseSensitive != null) 'case_sensitive': caseSensitive,
    if (spec == CharacterCardSpec.v3 || useRegex) 'use_regex': useRegex,
    if (name != null) 'name': name,
    if (priority != null) 'priority': priority,
    if (sourceId != null) 'id': sourceId,
    if (comment != null) 'comment': comment,
    if (selective != null) 'selective': selective,
    if (secondaryKeys.isNotEmpty)
      'secondary_keys': List<String>.from(secondaryKeys),
    if (constant != null) 'constant': constant,
    if (position != null) 'position': position,
  };
}

Map<String, dynamic> _copyJsonMap(Map<String, dynamic> source) {
  return source.map((key, value) => MapEntry(key, _copyJsonValue(value)));
}

dynamic _copyJsonValue(dynamic value) {
  if (value is Map) {
    return value.map(
      (key, nested) => MapEntry(key.toString(), _copyJsonValue(nested)),
    );
  }
  if (value is List) {
    return value.map(_copyJsonValue).toList(growable: false);
  }
  return value;
}

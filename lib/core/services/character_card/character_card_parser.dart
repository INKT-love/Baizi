import 'dart:convert';
import 'dart:typed_data';

import '../../models/character_card.dart';
import 'png_character_card_reader.dart';

class CharacterCardParser {
  const CharacterCardParser({
    this.limits = CharacterCardLimits.defaults,
    this.pngReader,
  });

  final CharacterCardLimits limits;
  final PngCharacterCardReader? pngReader;

  CharacterCardDocument parsePngBytes(Uint8List bytes) {
    final payload =
        pngReader?.read(bytes) ??
        PngCharacterCardReader(limits: limits).read(bytes);
    final card = parseJsonString(payload.jsonText);
    if (payload.keyword == 'ccv3' && card.spec != CharacterCardSpec.v3) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidCard,
        'PNG ccv3 metadata must contain a V3 character card.',
      );
    }
    return card;
  }

  CharacterCardDocument parseJsonBytes(List<int> bytes) {
    if (bytes.length > limits.maxJsonBytes) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.jsonTooLarge,
        'Character card JSON exceeds ${limits.maxJsonBytes} bytes.',
      );
    }

    String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException catch (error) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.invalidUtf8,
        'Character card JSON is not valid UTF-8: ${error.message}',
      );
    }
    return _parseDecodedJson(_stripBom(source));
  }

  CharacterCardDocument parseJsonString(String source) {
    final normalized = _stripBom(source);
    if (utf8.encode(normalized).length > limits.maxJsonBytes) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.jsonTooLarge,
        'Character card JSON exceeds ${limits.maxJsonBytes} bytes.',
      );
    }
    return _parseDecodedJson(normalized);
  }

  CharacterCardDocument _parseDecodedJson(String source) {
    _validateJsonDepth(source);

    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.invalidJson,
        'Character card contains invalid JSON: ${error.message}',
      );
    }

    _validateNodeCount(decoded);
    if (decoded is! Map) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidCard,
        'Character card root must be a JSON object.',
      );
    }

    final root = _stringKeyedMap(decoded, 'character card root');
    final rawSpec = root['spec'];
    if (!root.containsKey('spec')) {
      return _validateCharacterName(_parseV1(root));
    }
    if (rawSpec is! String) {
      throw _invalidField('spec', 'a string');
    }

    return _validateCharacterName(switch (rawSpec) {
      'chara_card_v2' => _parseWrapped(root, CharacterCardSpec.v2),
      'chara_card_v3' => _parseWrapped(root, CharacterCardSpec.v3),
      _ => throw CharacterCardParseException(
        CharacterCardParseErrorCode.unsupportedSpec,
        'Unsupported character card specification: $rawSpec.',
      ),
    });
  }

  CharacterCardDocument _validateCharacterName(CharacterCardDocument document) {
    if (document.data.name.trim().isEmpty) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidCard,
        'Character card name cannot be empty.',
      );
    }
    return document;
  }

  CharacterCardDocument _parseV1(Map<String, dynamic> root) {
    const requiredFields = <String>{
      'name',
      'description',
      'personality',
      'scenario',
      'first_mes',
      'mes_example',
    };
    if (!requiredFields.every(root.containsKey)) {
      throw const CharacterCardParseException(
        CharacterCardParseErrorCode.invalidCard,
        'V1 character cards must contain all six standard fields.',
      );
    }

    return CharacterCardDocument(
      spec: CharacterCardSpec.v1,
      specVersion: '1.0',
      data: CharacterCardData(
        name: _string(root, 'name'),
        description: _string(root, 'description'),
        personality: _string(root, 'personality'),
        scenario: _string(root, 'scenario'),
        firstMes: _string(root, 'first_mes'),
        mesExample: _string(root, 'mes_example'),
      ),
      unknownFields: _unknownFields(root, requiredFields),
    );
  }

  CharacterCardDocument _parseWrapped(
    Map<String, dynamic> root,
    CharacterCardSpec spec,
  ) {
    final rawData = root['data'];
    if (rawData is! Map) {
      throw _invalidField('data', 'an object');
    }
    final data = _stringKeyedMap(rawData, 'data');
    final defaultVersion = spec == CharacterCardSpec.v2 ? '2.0' : '3.0';
    final specVersion = _optionalString(root, 'spec_version') ?? defaultVersion;

    const v2KnownFields = <String>{
      'name',
      'description',
      'personality',
      'scenario',
      'first_mes',
      'mes_example',
      'creator_notes',
      'system_prompt',
      'post_history_instructions',
      'alternate_greetings',
      'character_book',
      'tags',
      'creator',
      'character_version',
      'extensions',
    };
    const v3Fields = <String>{
      'assets',
      'nickname',
      'creator_notes_multilingual',
      'source',
      'group_only_greetings',
      'creation_date',
      'modification_date',
    };
    final knownFields = <String>{
      ...v2KnownFields,
      if (spec == CharacterCardSpec.v3) ...v3Fields,
    };

    return CharacterCardDocument(
      spec: spec,
      specVersion: specVersion,
      data: CharacterCardData(
        name: _string(data, 'name'),
        description: _string(data, 'description'),
        personality: _string(data, 'personality'),
        scenario: _string(data, 'scenario'),
        firstMes: _string(data, 'first_mes'),
        mesExample: _string(data, 'mes_example'),
        creatorNotes: _string(data, 'creator_notes'),
        systemPrompt: _string(data, 'system_prompt'),
        postHistoryInstructions: _string(data, 'post_history_instructions'),
        alternateGreetings: _stringList(data, 'alternate_greetings'),
        characterBook: _characterBook(data['character_book'], spec),
        tags: _stringList(data, 'tags'),
        creator: _string(data, 'creator'),
        characterVersion: _string(data, 'character_version'),
        extensions: _jsonObject(data, 'extensions'),
        assets: spec == CharacterCardSpec.v3
            ? _assets(data['assets'])
            : const <CharacterCardAsset>[],
        nickname: spec == CharacterCardSpec.v3
            ? _optionalString(data, 'nickname')
            : null,
        creatorNotesMultilingual: spec == CharacterCardSpec.v3
            ? _stringMap(data, 'creator_notes_multilingual')
            : const <String, String>{},
        source: spec == CharacterCardSpec.v3
            ? _stringList(data, 'source')
            : const <String>[],
        groupOnlyGreetings: spec == CharacterCardSpec.v3
            ? _stringList(data, 'group_only_greetings')
            : const <String>[],
        creationDate: spec == CharacterCardSpec.v3
            ? _optionalInt(data, 'creation_date')
            : null,
        modificationDate: spec == CharacterCardSpec.v3
            ? _optionalInt(data, 'modification_date')
            : null,
        unknownFields: _unknownFields(data, knownFields),
      ),
      unknownFields: _unknownFields(root, const <String>{
        'spec',
        'spec_version',
        'data',
      }),
    );
  }

  CharacterBookData? _characterBook(dynamic raw, CharacterCardSpec spec) {
    if (raw == null) return null;
    if (raw is! Map) throw _invalidField('character_book', 'an object');
    final book = _stringKeyedMap(raw, 'character_book');
    const knownFields = <String>{
      'name',
      'description',
      'scan_depth',
      'token_budget',
      'recursive_scanning',
      'extensions',
      'entries',
    };

    final entriesRaw = book['entries'];
    final entries = <CharacterBookEntryData>[];
    if (entriesRaw != null) {
      if (entriesRaw is! List) {
        throw _invalidField('character_book.entries', 'an array');
      }
      for (var index = 0; index < entriesRaw.length; index++) {
        final rawEntry = entriesRaw[index];
        if (rawEntry is! Map) {
          throw _invalidField('character_book.entries[$index]', 'an object');
        }
        entries.add(
          _characterBookEntry(
            _stringKeyedMap(rawEntry, 'character_book.entries[$index]'),
            spec,
            index,
          ),
        );
      }
    }

    return CharacterBookData(
      name: _optionalString(book, 'name'),
      description: _optionalString(book, 'description'),
      scanDepth: _optionalInt(book, 'scan_depth'),
      tokenBudget: _optionalInt(book, 'token_budget'),
      recursiveScanning: _optionalBool(book, 'recursive_scanning'),
      extensions: _jsonObject(book, 'extensions'),
      entries: entries,
      unknownFields: _unknownFields(book, knownFields),
    );
  }

  CharacterBookEntryData _characterBookEntry(
    Map<String, dynamic> entry,
    CharacterCardSpec spec,
    int index,
  ) {
    final knownFields = <String>{
      'keys',
      'content',
      'extensions',
      'enabled',
      'insertion_order',
      'case_sensitive',
      if (spec == CharacterCardSpec.v3) 'use_regex',
      'name',
      'priority',
      'id',
      'comment',
      'selective',
      'secondary_keys',
      'constant',
      'position',
    };
    final sourceId = entry['id'];
    if (sourceId != null && sourceId is! String && sourceId is! num) {
      throw _invalidField(
        'character_book.entries[$index].id',
        'a string or number',
      );
    }

    return CharacterBookEntryData(
      keys: _stringList(entry, 'keys'),
      content: _string(entry, 'content'),
      extensions: _jsonObject(entry, 'extensions'),
      enabled: _bool(entry, 'enabled', defaultValue: true),
      insertionOrder: _int(entry, 'insertion_order', defaultValue: 0),
      caseSensitive: _optionalBool(entry, 'case_sensitive'),
      useRegex: _bool(entry, 'use_regex', defaultValue: false),
      name: _optionalString(entry, 'name'),
      priority: _optionalInt(entry, 'priority'),
      sourceId: sourceId,
      comment: _optionalString(entry, 'comment'),
      selective: _optionalBool(entry, 'selective'),
      secondaryKeys: _stringList(entry, 'secondary_keys'),
      constant: _optionalBool(entry, 'constant'),
      position: _optionalString(entry, 'position'),
      unknownFields: _unknownFields(entry, knownFields),
    );
  }

  List<CharacterCardAsset> _assets(dynamic raw) {
    if (raw == null) return const <CharacterCardAsset>[];
    if (raw is! List) throw _invalidField('assets', 'an array');

    return List<CharacterCardAsset>.generate(raw.length, (index) {
      final value = raw[index];
      if (value is! Map) {
        throw _invalidField('assets[$index]', 'an object');
      }
      final asset = _stringKeyedMap(value, 'assets[$index]');
      return CharacterCardAsset(
        type: _string(asset, 'type'),
        uri: _string(asset, 'uri'),
        name: _string(asset, 'name'),
        ext: _string(asset, 'ext'),
        unknownFields: _unknownFields(asset, const <String>{
          'type',
          'uri',
          'name',
          'ext',
        }),
      );
    }, growable: false);
  }

  void _validateJsonDepth(String source) {
    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var index = 0; index < source.length; index++) {
      final unit = source.codeUnitAt(index);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == 0x22) {
          inString = false;
        }
        continue;
      }

      if (unit == 0x22) {
        inString = true;
      } else if (unit == 0x7b || unit == 0x5b) {
        depth++;
        if (depth > limits.maxJsonDepth) {
          throw CharacterCardParseException(
            CharacterCardParseErrorCode.jsonTooDeep,
            'Character card JSON exceeds depth ${limits.maxJsonDepth}.',
          );
        }
      } else if (unit == 0x7d || unit == 0x5d) {
        depth--;
      }
    }
  }

  void _validateNodeCount(dynamic root) {
    final stack = <dynamic>[root];
    var count = 0;
    while (stack.isNotEmpty) {
      final value = stack.removeLast();
      count++;
      if (count > limits.maxJsonNodes) {
        throw CharacterCardParseException(
          CharacterCardParseErrorCode.jsonTooManyNodes,
          'Character card JSON exceeds ${limits.maxJsonNodes} nodes.',
        );
      }
      if (value is Map) {
        stack.addAll(value.values);
      } else if (value is List) {
        stack.addAll(value);
      }
    }
  }
}

String _stripBom(String source) {
  return source.startsWith('\uFEFF') ? source.substring(1) : source;
}

Map<String, dynamic> _stringKeyedMap(Map source, String path) {
  final result = <String, dynamic>{};
  for (final entry in source.entries) {
    if (entry.key is! String) {
      throw CharacterCardParseException(
        CharacterCardParseErrorCode.invalidField,
        '$path contains a non-string key.',
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

Map<String, dynamic> _unknownFields(
  Map<String, dynamic> source,
  Set<String> knownFields,
) {
  return <String, dynamic>{
    for (final entry in source.entries)
      if (!knownFields.contains(entry.key)) entry.key: entry.value,
  };
}

String _string(Map<String, dynamic> source, String key) {
  if (!source.containsKey(key)) return '';
  final value = source[key];
  if (value is String) return value;
  throw _invalidField(key, 'a string');
}

String? _optionalString(Map<String, dynamic> source, String key) {
  if (!source.containsKey(key) || source[key] == null) return null;
  final value = source[key];
  if (value is String) return value;
  throw _invalidField(key, 'a string');
}

List<String> _stringList(Map<String, dynamic> source, String key) {
  if (!source.containsKey(key) || source[key] == null) return const <String>[];
  final value = source[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw _invalidField(key, 'an array of strings');
  }
  return value.cast<String>().toList(growable: false);
}

Map<String, String> _stringMap(Map<String, dynamic> source, String key) {
  if (!source.containsKey(key) || source[key] == null) {
    return const <String, String>{};
  }
  final value = source[key];
  if (value is! Map) throw _invalidField(key, 'an object of strings');
  final result = <String, String>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! String) {
      throw _invalidField(key, 'an object of strings');
    }
    result[entry.key as String] = entry.value as String;
  }
  return result;
}

Map<String, dynamic> _jsonObject(Map<String, dynamic> source, String key) {
  if (!source.containsKey(key) || source[key] == null) {
    return const <String, dynamic>{};
  }
  final value = source[key];
  if (value is! Map) throw _invalidField(key, 'an object');
  return _stringKeyedMap(value, key);
}

bool _bool(
  Map<String, dynamic> source,
  String key, {
  required bool defaultValue,
}) {
  if (!source.containsKey(key) || source[key] == null) return defaultValue;
  final value = source[key];
  if (value is bool) return value;
  throw _invalidField(key, 'a boolean');
}

bool? _optionalBool(Map<String, dynamic> source, String key) {
  if (!source.containsKey(key) || source[key] == null) return null;
  final value = source[key];
  if (value is bool) return value;
  throw _invalidField(key, 'a boolean');
}

int _int(Map<String, dynamic> source, String key, {required int defaultValue}) {
  return _optionalInt(source, key) ?? defaultValue;
}

int? _optionalInt(Map<String, dynamic> source, String key) {
  if (!source.containsKey(key) || source[key] == null) return null;
  final value = source[key];
  if (value is int) return value;
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  throw _invalidField(key, 'an integer');
}

CharacterCardParseException _invalidField(String key, String expected) {
  return CharacterCardParseException(
    CharacterCardParseErrorCode.invalidField,
    'Character card field "$key" must be $expected.',
  );
}

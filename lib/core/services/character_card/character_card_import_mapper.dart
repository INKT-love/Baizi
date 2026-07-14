import '../../models/assistant_character_data.dart';
import '../../models/character_card.dart';
import '../../models/world_book.dart';

typedef CharacterCardEntryIdFactory =
    String Function(int index, Object? sourceId);

class CharacterCardImportMapping {
  const CharacterCardImportMapping({
    required this.name,
    required this.isPng,
    required this.characterData,
    required this.worldBook,
  });

  final String name;
  final bool isPng;
  final AssistantCharacterData characterData;
  final WorldBook? worldBook;
}

class CharacterCardImportMapper {
  const CharacterCardImportMapper();

  CharacterCardImportMapping map(
    CharacterCardDocument document, {
    required String sourceFileName,
    required bool isPng,
    required String worldBookId,
    required CharacterCardEntryIdFactory entryIdFactory,
  }) {
    final source = document.data;
    final worldBook = source.characterBook == null
        ? null
        : _mapWorldBook(
            source.characterBook!,
            fallbackName: source.name,
            worldBookId: worldBookId,
            entryIdFactory: entryIdFactory,
          );

    return CharacterCardImportMapping(
      name: source.name,
      isPng: isPng,
      characterData: AssistantCharacterData(
        cardVersion: document.specVersion,
        description: source.description,
        personality: source.personality,
        scenario: source.scenario,
        systemPrompt: source.systemPrompt,
        postHistoryInstructions: source.postHistoryInstructions,
        firstMes: source.firstMes,
        alternateGreetings: source.alternateGreetings,
        mesExample: source.mesExample,
        cardTags: source.tags,
        cardWorldBookId: worldBook?.id,
        sourceFileName: sourceFileName,
        extensions: source.extensions,
        unknownFields: _preservedFields(document),
      ),
      worldBook: worldBook,
    );
  }
}

WorldBook _mapWorldBook(
  CharacterBookData source, {
  required String fallbackName,
  required String worldBookId,
  required CharacterCardEntryIdFactory entryIdFactory,
}) {
  final id = _requireId(worldBookId, 'worldBookId');
  final bookScanDepth = _depth(source.scanDepth, fallback: 4);
  final entries = List<WorldBookEntry>.generate(source.entries.length, (index) {
    final entry = source.entries[index];
    final entryId = _requireId(
      entryIdFactory(index, entry.sourceId),
      'entryIdFactory($index)',
    );
    final position = _position(entry);

    return WorldBookEntry(
      id: entryId,
      name: _preferredText(entry.name, entry.comment),
      enabled: entry.enabled,
      priority: entry.priority ?? entry.insertionOrder,
      position: position,
      content: entry.content,
      injectDepth: _depth(entry.extensions['depth'], fallback: 4),
      role: _role(entry.extensions['role']),
      keywords: List<String>.unmodifiable(
        entry.keys.map((key) => key.trim()).where((key) => key.isNotEmpty),
      ),
      selective: entry.selective ?? false,
      secondaryKeywords: List<String>.unmodifiable(
        entry.secondaryKeys
            .map((key) => key.trim())
            .where((key) => key.isNotEmpty),
      ),
      useRegex: entry.useRegex,
      caseSensitive:
          entry.caseSensitive ??
          _extensionBool(entry.extensions, 'case_sensitive') ??
          false,
      scanDepth: _depth(
        entry.extensions['scan_depth'],
        fallback: bookScanDepth,
      ),
      constantActive:
          entry.constant ??
          _extensionBool(entry.extensions, 'constant') ??
          false,
    );
  }, growable: false);

  return WorldBook(
    id: id,
    name: _preferredText(source.name, fallbackName),
    description: source.description ?? '',
    entries: List<WorldBookEntry>.unmodifiable(entries),
  );
}

Map<String, dynamic> _preservedFields(CharacterCardDocument document) {
  final preserved = <String, dynamic>{};
  if (document.unknownFields.isNotEmpty) {
    preserved['root'] = document.unknownFields;
  }

  final source = document.data;
  final data = <String, dynamic>{...source.unknownFields};
  if (document.spec != CharacterCardSpec.v1) {
    data.addAll(<String, dynamic>{
      'creator_notes': source.creatorNotes,
      'creator': source.creator,
      'character_version': source.characterVersion,
      if (source.characterBook != null)
        'character_book': source.characterBook!.toJson(document.spec),
    });
  }

  if (document.spec == CharacterCardSpec.v3) {
    data.addAll(<String, dynamic>{
      if (source.assets.isNotEmpty)
        'assets': source.assets.map((asset) => asset.toJson()).toList(),
      if (source.nickname != null) 'nickname': source.nickname,
      if (source.creatorNotesMultilingual.isNotEmpty)
        'creator_notes_multilingual': source.creatorNotesMultilingual,
      if (source.source.isNotEmpty) 'source': source.source,
      'group_only_greetings': source.groupOnlyGreetings,
      if (source.creationDate != null) 'creation_date': source.creationDate,
      if (source.modificationDate != null)
        'modification_date': source.modificationDate,
    });
  }

  if (data.isNotEmpty) preserved['data'] = data;
  return preserved;
}

WorldBookInjectionPosition _position(CharacterBookEntryData entry) {
  final explicit = entry.position?.trim();
  final raw = explicit == null || explicit.isEmpty
      ? entry.extensions['position']
      : explicit;
  if (raw is! String) {
    return WorldBookInjectionPosition.afterSystemPrompt;
  }

  final value = raw
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  return switch (value) {
    'before_char' ||
    'before_character' ||
    'before_system' ||
    'before_system_prompt' => WorldBookInjectionPosition.beforeSystemPrompt,
    'after_char' ||
    'after_character' ||
    'after_system' ||
    'after_system_prompt' => WorldBookInjectionPosition.afterSystemPrompt,
    'top' || 'top_of_chat' => WorldBookInjectionPosition.topOfChat,
    'bottom' || 'bottom_of_chat' => WorldBookInjectionPosition.bottomOfChat,
    'at_depth' || 'depth' => WorldBookInjectionPosition.atDepth,
    _ => WorldBookInjectionPosition.afterSystemPrompt,
  };
}

WorldBookInjectionRole _role(Object? raw) {
  if (raw is String && raw.trim().toLowerCase() == 'assistant') {
    return WorldBookInjectionRole.assistant;
  }
  return WorldBookInjectionRole.user;
}

bool? _extensionBool(Map<String, dynamic> extensions, String key) {
  final value = extensions[key];
  return value is bool ? value : null;
}

int _depth(Object? value, {required int fallback}) {
  if (value is! int || value < 1 || value > 200) return fallback;
  return value;
}

String _preferredText(String? preferred, String? fallback) {
  final value = preferred?.trim();
  if (value != null && value.isNotEmpty) return value;
  return fallback?.trim() ?? '';
}

String _requireId(String value, String argumentName) {
  final id = value.trim();
  if (id.isEmpty) {
    throw ArgumentError.value(
      value,
      argumentName,
      'Identifier cannot be empty',
    );
  }
  return id;
}

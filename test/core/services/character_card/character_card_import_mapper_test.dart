import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/character_card.dart';
import 'package:Kelivo/core/models/world_book.dart';
import 'package:Kelivo/core/services/character_card/character_card_import_mapper.dart';

void main() {
  const mapper = CharacterCardImportMapper();

  group('CharacterCardImportMapper character data', () {
    test('maps all direct fields and preserves V3-only and unknown data', () {
      final document = CharacterCardDocument(
        spec: CharacterCardSpec.v3,
        specVersion: '3.1',
        unknownFields: const <String, dynamic>{
          'root_future': <String, dynamic>{'kept': true},
        },
        data: CharacterCardData(
          name: 'Archivist',
          description: 'A careful archivist.',
          personality: 'Calm and curious.',
          scenario: 'An old library.',
          firstMes: 'Welcome, {{user}}.',
          mesExample: '<START>\n{{user}}: Hello\n{{char}}: Welcome.',
          creatorNotes: 'Keep these notes.',
          systemPrompt: 'Stay in character.',
          postHistoryInstructions: 'Answer concisely.',
          alternateGreetings: const <String>['Need a book?', 'Hello again.'],
          tags: const <String>['archive', 'helper'],
          creator: 'Card Maker',
          characterVersion: '1.4',
          extensions: const <String, dynamic>{
            'depth_prompt': <String, dynamic>{
              'depth': 4,
              'prompt': 'Remember the archive.',
            },
          },
          assets: <CharacterCardAsset>[
            CharacterCardAsset(
              type: 'icon',
              uri: 'ccdefault:',
              name: 'main',
              ext: 'png',
              unknownFields: const <String, dynamic>{'asset_future': 1},
            ),
          ],
          nickname: 'Archive Keeper',
          creatorNotesMultilingual: const <String, String>{
            'en': 'Keep these notes.',
            'zh': '保留这些备注。',
          },
          source: const <String>['https://example.invalid/card'],
          groupOnlyGreetings: const <String>['Welcome, everyone.'],
          creationDate: 1700000000,
          modificationDate: 1700001000,
          unknownFields: const <String, dynamic>{
            'data_future': <dynamic>['kept', 2],
          },
        ),
      );

      final result = mapper.map(
        document,
        sourceFileName: 'imports/archivist.png',
        isPng: true,
        worldBookId: 'assistant-1:world-book',
        entryIdFactory: (index, sourceId) => 'unused-$index-$sourceId',
      );

      expect(result.name, 'Archivist');
      expect(result.isPng, isTrue);
      expect(result.worldBook, isNull);

      final data = result.characterData;
      expect(data.cardVersion, '3.1');
      expect(data.description, 'A careful archivist.');
      expect(data.personality, 'Calm and curious.');
      expect(data.scenario, 'An old library.');
      expect(data.systemPrompt, 'Stay in character.');
      expect(data.postHistoryInstructions, 'Answer concisely.');
      expect(data.firstMes, 'Welcome, {{user}}.');
      expect(data.alternateGreetings, ['Need a book?', 'Hello again.']);
      expect(data.mesExample, contains('{{char}}: Welcome.'));
      expect(data.cardTags, ['archive', 'helper']);
      expect(data.cardWorldBookId, isNull);
      expect(data.sourceFileName, 'imports/archivist.png');
      expect(data.extensions, document.data.extensions);
      expect(data.unknownFields['root'], document.unknownFields);

      final preservedData = data.unknownFields['data'] as Map<String, dynamic>;
      expect(preservedData['data_future'], ['kept', 2]);
      expect(preservedData['creator_notes'], 'Keep these notes.');
      expect(preservedData['creator'], 'Card Maker');
      expect(preservedData['character_version'], '1.4');
      expect(preservedData['nickname'], 'Archive Keeper');
      expect(preservedData['creator_notes_multilingual'], {
        'en': 'Keep these notes.',
        'zh': '保留这些备注。',
      });
      expect(preservedData['source'], ['https://example.invalid/card']);
      expect(preservedData['group_only_greetings'], ['Welcome, everyone.']);
      expect(preservedData['creation_date'], 1700000000);
      expect(preservedData['modification_date'], 1700001000);
      expect(preservedData['assets'], [
        {
          'asset_future': 1,
          'type': 'icon',
          'uri': 'ccdefault:',
          'name': 'main',
          'ext': 'png',
        },
      ]);
    });

    test('keeps JSON source files and V1 root extensions', () {
      final document = CharacterCardDocument(
        spec: CharacterCardSpec.v1,
        specVersion: '1.0',
        unknownFields: const <String, dynamic>{
          'talkativeness': 0.7,
          'future': <String, dynamic>{'enabled': true},
        },
        data: CharacterCardData(
          name: 'V1 Character',
          description: 'Description',
          personality: 'Personality',
          scenario: 'Scenario',
          firstMes: 'First',
          mesExample: 'Example',
        ),
      );

      final result = mapper.map(
        document,
        sourceFileName: 'imports/v1-card.json',
        isPng: false,
        worldBookId: 'unused-book-id',
        entryIdFactory: (index, sourceId) => 'unused-entry-id',
      );

      expect(result.isPng, isFalse);
      expect(result.characterData.sourceFileName, 'imports/v1-card.json');
      expect(result.characterData.unknownFields, {
        'root': {
          'talkativeness': 0.7,
          'future': {'enabled': true},
        },
      });
    });

    test('rejects a source path outside the managed import directory', () {
      expect(
        () => mapper.map(
          _document(),
          sourceFileName: '../outside/card.json',
          isPng: false,
          worldBookId: 'unused-book-id',
          entryIdFactory: (index, sourceId) => 'unused-entry-id',
        ),
        throwsArgumentError,
      );
    });
  });

  group('CharacterCardImportMapper world book', () {
    test('maps supported entry semantics including selective keys', () {
      final seenIds = <(int, Object?)>[];
      final bookData = CharacterBookData(
        name: 'Archive lore',
        description: 'Facts about the archive.',
        scanDepth: 8,
        tokenBudget: 2048,
        recursiveScanning: true,
        extensions: const <String, dynamic>{'book_extension': 'kept'},
        unknownFields: const <String, dynamic>{'book_future': true},
        entries: <CharacterBookEntryData>[
          CharacterBookEntryData(
            keys: const <String>['archive', '  ', 'vault'],
            content: 'The archive closes at midnight.',
            enabled: true,
            insertionOrder: 7,
            caseSensitive: true,
            useRegex: true,
            name: 'Closing time',
            priority: 42,
            sourceId: 99,
            selective: true,
            secondaryKeys: const <String>['night'],
            constant: true,
            position: 'before_char',
            extensions: const <String, dynamic>{
              'scan_depth': 12,
              'depth': 6,
              'role': 'assistant',
              'position': 'at_depth',
              'case_sensitive': false,
              'constant': false,
              'use_regex': false,
              'entry_extension': 'kept',
            },
            unknownFields: const <String, dynamic>{'entry_future': 3},
          ),
          CharacterBookEntryData(
            keys: const <String>['library'],
            content: 'The library has three floors.',
            insertionOrder: 11,
            sourceId: 'floor-entry',
            comment: 'Floor count',
            position: 'at_depth',
            extensions: const <String, dynamic>{'depth': 3},
          ),
        ],
      );
      final document = _document(characterBook: bookData);

      final result = mapper.map(
        document,
        sourceFileName: 'imports/archive.json',
        isPng: false,
        worldBookId: 'assistant-1:world-book',
        entryIdFactory: (index, sourceId) {
          seenIds.add((index, sourceId));
          return 'assistant-1:entry:$index';
        },
      );

      expect(seenIds, [(0, 99), (1, 'floor-entry')]);
      expect(result.characterData.cardWorldBookId, 'assistant-1:world-book');

      final book = result.worldBook!;
      expect(book.id, 'assistant-1:world-book');
      expect(book.name, 'Archive lore');
      expect(book.description, 'Facts about the archive.');
      expect(book.enabled, isTrue);
      expect(book.entries, hasLength(2));

      final first = book.entries.first;
      expect(first.id, 'assistant-1:entry:0');
      expect(first.name, 'Closing time');
      expect(first.enabled, isTrue);
      expect(first.priority, 42);
      expect(first.position, WorldBookInjectionPosition.beforeSystemPrompt);
      expect(first.content, 'The archive closes at midnight.');
      expect(first.injectDepth, 6);
      expect(first.role, WorldBookInjectionRole.assistant);
      expect(first.keywords, ['archive', 'vault']);
      expect(first.keywords, isNot(contains('night')));
      expect(first.selective, isTrue);
      expect(first.secondaryKeywords, ['night']);
      expect(first.useRegex, isTrue);
      expect(first.caseSensitive, isTrue);
      expect(first.scanDepth, 12);
      expect(first.constantActive, isTrue);

      final second = book.entries.last;
      expect(second.id, 'assistant-1:entry:1');
      expect(second.name, 'Floor count');
      expect(second.priority, 11);
      expect(second.position, WorldBookInjectionPosition.atDepth);
      expect(second.injectDepth, 3);
      expect(second.role, WorldBookInjectionRole.user);
      expect(second.scanDepth, 8);
      expect(second.selective, isFalse);
      expect(second.secondaryKeywords, isEmpty);

      final decodedFirst = WorldBookEntry.fromJson(first.toJson());
      expect(decodedFirst.selective, isTrue);
      expect(decodedFirst.secondaryKeywords, ['night']);

      final preservedBook =
          (result.characterData.unknownFields['data']
                  as Map<String, dynamic>)['character_book']
              as Map<String, dynamic>;
      expect(preservedBook, bookData.toJson(CharacterCardSpec.v3));
    });

    test('uses safe defaults and only recognizes explicit positions', () {
      final document = _document(
        characterBook: CharacterBookData(
          scanDepth: 999,
          entries: <CharacterBookEntryData>[
            CharacterBookEntryData(
              position: 'after_char',
              caseSensitive: false,
              useRegex: false,
              constant: false,
              extensions: const <String, dynamic>{
                'position': 'before_char',
                'case_sensitive': true,
                'constant': true,
                'use_regex': true,
              },
            ),
            CharacterBookEntryData(position: 'top_of_chat'),
            CharacterBookEntryData(position: 'bottom_of_chat'),
            CharacterBookEntryData(
              extensions: const <String, dynamic>{
                'position': 'at_depth',
                'depth': 3,
                'scan_depth': 12,
                'role': 'assistant',
                'case_sensitive': true,
                'constant': true,
                'use_regex': true,
              },
            ),
            CharacterBookEntryData(
              position: 'some_future_position',
              extensions: const <String, dynamic>{
                'position': 'before_char',
                'depth': 0,
                'scan_depth': 201,
                'role': 'system',
                'case_sensitive': 'true',
                'constant': 1,
              },
            ),
          ],
        ),
      );

      final entries = mapper
          .map(
            document,
            sourceFileName: 'imports/defaults.json',
            isPng: false,
            worldBookId: 'book-id',
            entryIdFactory: (index, sourceId) => 'entry-$index',
          )
          .worldBook!
          .entries;

      expect(entries.map((entry) => entry.position), [
        WorldBookInjectionPosition.afterSystemPrompt,
        WorldBookInjectionPosition.topOfChat,
        WorldBookInjectionPosition.bottomOfChat,
        WorldBookInjectionPosition.atDepth,
        WorldBookInjectionPosition.afterSystemPrompt,
      ]);
      expect(entries[0].caseSensitive, isFalse);
      expect(entries[0].constantActive, isFalse);
      expect(entries[0].useRegex, isFalse);
      expect(entries[3].injectDepth, 3);
      expect(entries[3].scanDepth, 12);
      expect(entries[3].role, WorldBookInjectionRole.assistant);
      expect(entries[3].caseSensitive, isTrue);
      expect(entries[3].constantActive, isTrue);
      expect(entries[3].useRegex, isFalse);
      expect(entries[4].injectDepth, 4);
      expect(entries[4].scanDepth, 4);
      expect(entries[4].role, WorldBookInjectionRole.user);
      expect(entries[4].caseSensitive, isFalse);
      expect(entries[4].constantActive, isFalse);
      expect(
        entries
            .where((entry) => entry != entries[3])
            .every((entry) => entry.scanDepth == 4),
        isTrue,
      );
    });

    test('rejects empty generated identifiers', () {
      final document = _document(
        characterBook: CharacterBookData(
          entries: <CharacterBookEntryData>[CharacterBookEntryData()],
        ),
      );

      expect(
        () => mapper.map(
          document,
          sourceFileName: 'imports/card.json',
          isPng: false,
          worldBookId: ' ',
          entryIdFactory: (index, sourceId) => 'entry-$index',
        ),
        throwsArgumentError,
      );
      expect(
        () => mapper.map(
          document,
          sourceFileName: 'imports/card.json',
          isPng: false,
          worldBookId: 'book-id',
          entryIdFactory: (index, sourceId) => ' ',
        ),
        throwsArgumentError,
      );
    });

    test('keeps legacy world book entries non-selective by default', () {
      final entry = WorldBookEntry.fromJson(<String, dynamic>{
        'id': 'legacy-entry',
        'keywords': <String>['archive'],
      });

      expect(entry.selective, isFalse);
      expect(entry.secondaryKeywords, isEmpty);
    });
  });
}

CharacterCardDocument _document({CharacterBookData? characterBook}) {
  return CharacterCardDocument(
    spec: CharacterCardSpec.v3,
    specVersion: '3.0',
    data: CharacterCardData(
      name: 'Archivist',
      description: 'Description',
      personality: 'Personality',
      scenario: 'Scenario',
      firstMes: 'First',
      mesExample: 'Example',
      characterBook: characterBook,
    ),
  );
}

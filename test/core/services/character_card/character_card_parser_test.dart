import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/character_card.dart';
import 'package:Kelivo/core/services/character_card/character_card_parser.dart';

Map<String, dynamic> _v1Card({Map<String, dynamic> extra = const {}}) => {
  ...extra,
  'name': 'Alice',
  'description': 'A curious traveler.',
  'personality': 'Kind',
  'scenario': 'A train station',
  'first_mes': 'Hello, {{user}}.',
  'mes_example': '<START>\n{{user}}: Hi\n{{char}}: Hello',
};

void main() {
  group('CharacterCardParser JSON normalization', () {
    test('normalizes V1 and preserves unknown root fields', () {
      final parser = const CharacterCardParser();
      final card = parser.parseJsonString(
        jsonEncode(
          _v1Card(
            extra: {
              'future_field': {
                'nested': [1, true, null],
              },
            },
          ),
        ),
      );

      expect(card.spec, CharacterCardSpec.v1);
      expect(card.specVersion, '1.0');
      expect(card.data.name, 'Alice');
      expect(card.data.firstMes, 'Hello, {{user}}.');
      expect(card.data.alternateGreetings, isEmpty);
      expect(card.unknownFields['future_field'], {
        'nested': [1, true, null],
      });

      final encoded = card.toJson();
      expect(encoded.containsKey('spec'), isFalse);
      expect(encoded['future_field'], {
        'nested': [1, true, null],
      });
    });

    test('normalizes all V2 fields and preserves nested unknown fields', () {
      final parser = const CharacterCardParser();
      final card = parser.parseJsonString(
        jsonEncode({
          'spec': 'chara_card_v2',
          'spec_version': '2.0',
          'root_future': 'keep-root',
          'data': {
            'name': 'V2 Alice',
            'description': 'Description',
            'personality': 'Personality',
            'scenario': 'Scenario',
            'first_mes': 'First',
            'mes_example': 'Examples',
            'creator_notes': 'Notes',
            'system_prompt': 'System',
            'post_history_instructions': 'Post',
            'alternate_greetings': ['Alt 1', 'Alt 2'],
            'tags': ['adventure', 'friendly'],
            'creator': 'Creator',
            'character_version': '1.2',
            'extensions': {
              'vendor': {'enabled': true},
            },
            'data_future': 42,
            'character_book': {
              'name': 'Alice lore',
              'description': 'Lore description',
              'scan_depth': 8,
              'token_budget': 1024,
              'recursive_scanning': true,
              'extensions': {'book_ext': 'keep'},
              'book_future': ['keep'],
              'entries': [
                {
                  'keys': ['station'],
                  'content': 'Station lore',
                  'extensions': {'entry_ext': 1},
                  'enabled': true,
                  'insertion_order': 7,
                  'case_sensitive': false,
                  'name': 'Station',
                  'priority': 10,
                  'id': 99,
                  'comment': 'Comment',
                  'selective': true,
                  'secondary_keys': ['train'],
                  'constant': false,
                  'position': 'before_char',
                  'entry_future': {'keep': true},
                },
              ],
            },
          },
        }),
      );

      expect(card.spec, CharacterCardSpec.v2);
      expect(card.unknownFields['root_future'], 'keep-root');
      expect(card.data.unknownFields['data_future'], 42);
      expect(card.data.alternateGreetings, ['Alt 1', 'Alt 2']);
      expect(card.data.extensions['vendor'], {'enabled': true});

      final book = card.data.characterBook!;
      expect(book.scanDepth, 8);
      expect(book.tokenBudget, 1024);
      expect(book.recursiveScanning, isTrue);
      expect(book.unknownFields['book_future'], ['keep']);

      final entry = book.entries.single;
      expect(entry.keys, ['station']);
      expect(entry.secondaryKeys, ['train']);
      expect(entry.sourceId, 99);
      expect(entry.useRegex, isFalse);
      expect(entry.unknownFields['entry_future'], {'keep': true});

      final encoded = card.toJson();
      expect(encoded['root_future'], 'keep-root');
      final data = encoded['data'] as Map<String, dynamic>;
      final encodedBook = data['character_book'] as Map<String, dynamic>;
      final encodedEntry = (encodedBook['entries'] as List).single as Map;
      expect(data['data_future'], 42);
      expect(encodedBook['book_future'], ['keep']);
      expect(encodedEntry['entry_future'], {'keep': true});
    });

    test('normalizes V3 additions and accepts future V3 minor versions', () {
      final parser = const CharacterCardParser();
      final card = parser.parseJsonString(
        jsonEncode({
          'spec': 'chara_card_v3',
          'spec_version': '3.1',
          'data': {
            'name': 'V3 Alice',
            'description': '',
            'personality': '',
            'scenario': '',
            'first_mes': 'Hello',
            'mes_example': '',
            'creator_notes': 'English notes',
            'system_prompt': '',
            'post_history_instructions': '',
            'alternate_greetings': [],
            'tags': [],
            'creator': '',
            'character_version': '',
            'extensions': {},
            'assets': [
              {
                'type': 'icon',
                'uri': 'ccdefault:',
                'name': 'main',
                'ext': 'png',
                'asset_future': 'keep',
              },
            ],
            'nickname': 'Al',
            'creator_notes_multilingual': {'en': 'English notes', 'zh': '中文备注'},
            'source': ['https://example.com/card'],
            'group_only_greetings': ['Hello, group'],
            'creation_date': 1700000000,
            'modification_date': 1700001000,
            'character_book': {
              'extensions': {},
              'entries': [
                {
                  'keys': [r'^Alice$'],
                  'content': 'Regex lore',
                  'extensions': {},
                  'enabled': true,
                  'insertion_order': 0,
                  'use_regex': true,
                  'constant': false,
                  'id': 'entry-id',
                },
              ],
            },
          },
        }),
      );

      expect(card.spec, CharacterCardSpec.v3);
      expect(card.specVersion, '3.1');
      expect(card.data.nickname, 'Al');
      expect(card.data.groupOnlyGreetings, ['Hello, group']);
      expect(card.data.creatorNotesMultilingual['zh'], '中文备注');
      expect(card.data.assets.single.unknownFields['asset_future'], 'keep');
      expect(card.data.characterBook!.entries.single.useRegex, isTrue);
      expect(card.data.characterBook!.entries.single.sourceId, 'entry-id');

      final roundTrip = parser.parseJsonString(jsonEncode(card.toJson()));
      expect(roundTrip.toJson(), card.toJson());
    });

    test('accepts a UTF-8 BOM', () {
      final parser = const CharacterCardParser();
      final bytes = Uint8List.fromList([
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(jsonEncode(_v1Card())),
      ]);

      expect(parser.parseJsonBytes(bytes).data.name, 'Alice');
    });

    test('rejects an unknown explicit specification', () {
      final parser = const CharacterCardParser();

      expect(
        () => parser.parseJsonString(
          jsonEncode({
            'spec': 'some_other_card',
            'spec_version': '1.0',
            'data': {},
          }),
        ),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.unsupportedSpec,
          ),
        ),
      );
    });

    test(
      'rejects an explicit null specification instead of treating it as V1',
      () {
        final parser = const CharacterCardParser();
        final invalid = _v1Card()..['spec'] = null;

        expect(
          () => parser.parseJsonString(jsonEncode(invalid)),
          throwsA(
            isA<CharacterCardParseException>().having(
              (error) => error.code,
              'code',
              CharacterCardParseErrorCode.invalidField,
            ),
          ),
        );
      },
    );

    test('rejects JSON that is not a complete V1 card', () {
      final parser = const CharacterCardParser();

      expect(
        () => parser.parseJsonString(jsonEncode({'name': 'Only a name'})),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.invalidCard,
          ),
        ),
      );
    });

    test('rejects empty and whitespace-only character names', () {
      final parser = const CharacterCardParser();
      final cards = <Map<String, dynamic>>[
        _v1Card()..['name'] = '',
        <String, dynamic>{
          'spec': 'chara_card_v3',
          'spec_version': '3.0',
          'data': <String, dynamic>{..._v1Card(), 'name': ' \t\n'},
        },
      ];

      for (final card in cards) {
        expect(
          () => parser.parseJsonString(jsonEncode(card)),
          throwsA(
            isA<CharacterCardParseException>().having(
              (error) => error.code,
              'code',
              CharacterCardParseErrorCode.invalidCard,
            ),
          ),
        );
      }
    });

    test('rejects invalid field types instead of coercing them', () {
      final parser = const CharacterCardParser();
      final invalid = _v1Card()..['first_mes'] = 123;

      expect(
        () => parser.parseJsonString(jsonEncode(invalid)),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.invalidField,
          ),
        ),
      );
    });
  });

  group('CharacterCardParser limits', () {
    test('rejects invalid UTF-8 before JSON decoding', () {
      final parser = const CharacterCardParser();

      expect(
        () => parser.parseJsonBytes(Uint8List.fromList([0xff, 0xfe])),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.invalidUtf8,
          ),
        ),
      );
    });

    test('rejects input larger than the configured decoded JSON limit', () {
      final parser = CharacterCardParser(
        limits: CharacterCardLimits.defaults.copyWith(maxJsonBytes: 16),
      );

      expect(
        () => parser.parseJsonBytes(Uint8List(17)),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.jsonTooLarge,
          ),
        ),
      );
    });

    test('rejects JSON nesting beyond the configured depth', () {
      final parser = CharacterCardParser(
        limits: CharacterCardLimits.defaults.copyWith(maxJsonDepth: 3),
      );
      final deep =
          '{"name":"Alice","description":"","personality":"",'
          '"scenario":"","first_mes":"","mes_example":"",'
          '"future":{"a":{"b":{"c":1}}}}';

      expect(
        () => parser.parseJsonString(deep),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.jsonTooDeep,
          ),
        ),
      );
    });

    test('rejects JSON beyond the configured node count', () {
      final parser = CharacterCardParser(
        limits: CharacterCardLimits.defaults.copyWith(maxJsonNodes: 10),
      );
      final card = _v1Card(
        extra: {'future': List<int>.generate(20, (index) => index)},
      );

      expect(
        () => parser.parseJsonString(jsonEncode(card)),
        throwsA(
          isA<CharacterCardParseException>().having(
            (error) => error.code,
            'code',
            CharacterCardParseErrorCode.jsonTooManyNodes,
          ),
        ),
      );
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Baizi/core/models/assistant.dart';
import 'package:Baizi/core/models/assistant_character_data.dart';

AssistantCharacterData _fullCharacterData() {
  return AssistantCharacterData(
    cardVersion: '3.0',
    description: 'A careful archivist.',
    personality: 'Calm and curious.',
    scenario: 'An old library.',
    systemPrompt: 'Stay in character.',
    postHistoryInstructions: 'Answer concisely.',
    firstMes: 'Welcome to the library.',
    alternateGreetings: const <String>['Hello again.', 'Need a book?'],
    mesExample: '<START>\n{{user}}: Hello\n{{char}}: Welcome.',
    cardTags: const <String>['archive', 'helper'],
    cardWorldBookId: 'world-book-1',
    sourceFileName: 'imports/archivist.png',
    extensions: const <String, dynamic>{
      'depth_prompt': <String, dynamic>{'depth': 4, 'prompt': 'Remember.'},
    },
    unknownFields: const <String, dynamic>{
      'future_field': <dynamic>[
        true,
        <String, dynamic>{'nested': 'kept'},
      ],
    },
  );
}

void main() {
  group('AssistantCharacterData JSON', () {
    test('round-trips all persisted character card fields', () {
      final original = _fullCharacterData();

      final decoded = AssistantCharacterData.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(decoded.toJson(), original.toJson());
      expect(decoded.cardVersion, '3.0');
      expect(decoded.alternateGreetings, ['Hello again.', 'Need a book?']);
      expect(decoded.cardWorldBookId, 'world-book-1');
      expect(decoded.sourceFileName, 'imports/archivist.png');
    });

    test('deep-copies and freezes extensions and unknown fields', () {
      final extensionItems = <dynamic>['original'];
      final unknownNested = <String, dynamic>{'enabled': true};
      final data = AssistantCharacterData(
        extensions: <String, dynamic>{'items': extensionItems},
        unknownFields: <String, dynamic>{'nested': unknownNested},
      );

      extensionItems.add('changed outside');
      unknownNested['enabled'] = false;

      expect(data.extensions, <String, dynamic>{
        'items': <dynamic>['original'],
      });
      expect(data.unknownFields, <String, dynamic>{
        'nested': <String, dynamic>{'enabled': true},
      });
      expect(
        () => (data.extensions['items'] as List<dynamic>).add('mutate'),
        throwsUnsupportedError,
      );
      expect(
        () =>
            (data.unknownFields['nested'] as Map<String, dynamic>)['enabled'] =
                false,
        throwsUnsupportedError,
      );
    });

    test('rejects extension values that cannot be persisted as JSON', () {
      expect(
        () => AssistantCharacterData(
          extensions: <String, dynamic>{
            'notJson': <String>{'value'},
          },
        ),
        throwsArgumentError,
      );
    });

    test('accepts only paths relative to the character cards directory', () {
      expect(
        AssistantCharacterData(
          sourceFileName: 'folder/card.json',
        ).sourceFileName,
        'folder/card.json',
      );

      for (final unsafePath in <String>[
        '',
        '../card.json',
        'nested/../../card.json',
        '/tmp/card.json',
        r'C:\cards\card.json',
        r'\\server\share\card.json',
        'file:///tmp/card.json',
      ]) {
        expect(
          () => AssistantCharacterData(sourceFileName: unsafePath),
          throwsArgumentError,
          reason: unsafePath,
        );
      }
    });

    test('drops an unsafe persisted source path without losing card data', () {
      final decoded = AssistantCharacterData.fromJson(<String, dynamic>{
        'cardVersion': '2.0',
        'firstMes': 'Still here.',
        'sourceFileName': '../outside.png',
        'unknownFields': <String, dynamic>{'future': 1},
      });

      expect(decoded.cardVersion, '2.0');
      expect(decoded.firstMes, 'Still here.');
      expect(decoded.sourceFileName, isNull);
      expect(decoded.unknownFields, <String, dynamic>{'future': 1});
    });
  });

  group('Assistant character data compatibility', () {
    test('keeps old assistant JSON compatible', () {
      final assistant = Assistant.fromJson(<String, dynamic>{
        'id': 'legacy-assistant',
        'name': 'Legacy',
        'systemPrompt': 'Existing prompt',
      });

      expect(assistant.characterData, isNull);
      expect(assistant.systemPrompt, 'Existing prompt');
      expect(assistant.toJson()['characterData'], isNull);
    });

    test('round-trips character data through assistant list persistence', () {
      final original = Assistant(
        id: 'character-assistant',
        name: 'Archivist',
        characterData: _fullCharacterData(),
      );

      final decoded = Assistant.decodeList(
        Assistant.encodeList(<Assistant>[original]),
      ).single;

      expect(decoded.characterData?.toJson(), original.characterData?.toJson());
    });

    test(
      'copyWith preserves, replaces, and explicitly clears character data',
      () {
        final characterData = _fullCharacterData();
        final assistant = Assistant(
          id: 'character-assistant',
          name: 'Archivist',
          characterData: characterData,
        );
        final replacement = AssistantCharacterData(firstMes: 'Replacement');

        expect(
          assistant.copyWith(id: 'copy', name: 'Archivist Copy').characterData,
          same(characterData),
        );
        expect(
          assistant.copyWith(characterData: replacement).characterData,
          same(replacement),
        );
        expect(
          assistant.copyWith(clearCharacterData: true).characterData,
          isNull,
        );
      },
    );

    test(
      'ignores a malformed character data value on otherwise valid JSON',
      () {
        final assistant = Assistant.fromJson(<String, dynamic>{
          'id': 'legacy-assistant',
          'name': 'Legacy',
          'characterData': 'not-an-object',
        });

        expect(assistant.characterData, isNull);
      },
    );
  });
}

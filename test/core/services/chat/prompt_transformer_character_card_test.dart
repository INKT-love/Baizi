import 'package:flutter_test/flutter_test.dart';

import 'package:Baizi/core/models/assistant.dart';
import 'package:Baizi/core/models/assistant_character_data.dart';
import 'package:Baizi/core/services/chat/prompt_transformer.dart';

void main() {
  test('builds card prompt components without creating history messages', () {
    final assistant = Assistant(
      id: 'card-1',
      name: 'Alice',
      systemPrompt: 'Manual rule',
      characterData: AssistantCharacterData(
        systemPrompt: 'You are {{char}}.',
        description: '{{char}} is a guide for {{user}}.',
        personality: 'Patient',
        scenario: '{{user}} arrives at the station.',
        mesExample: '{{user}}: Hello\n{{char}}: Welcome',
        postHistoryInstructions: 'Always address {{user}} by name.',
      ),
    );

    final system = PromptTransformer.buildCharacterCardSystemPrompt(
      assistant,
      userNickname: 'Bob',
    );
    final post = PromptTransformer.buildCharacterCardPostHistoryInstructions(
      assistant,
      userNickname: 'Bob',
    );

    expect(system, contains('Manual rule'));
    expect(system, contains('You are Alice.'));
    expect(system, contains('<character_description>'));
    expect(system, contains('Alice is a guide for Bob.'));
    expect(system, contains('<example_dialogue>'));
    expect(system, contains('Bob: Hello\nAlice: Welcome'));
    expect(post, 'Always address Bob by name.');
    expect(system, isNot(contains('Always address Bob by name.')));
  });

  test('replaces Tavern placeholders case-insensitively', () {
    expect(
      PromptTransformer.replaceCharacterCardPlaceholders(
        '{{ CHAR }} meets {{User}} and {{unknown}}',
        characterName: '白子',
        userNickname: '用户',
      ),
      '白子 meets 用户 and {{unknown}}',
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Baizi/core/models/assistant.dart';
import 'package:Baizi/core/models/assistant_character_data.dart';
import 'package:Baizi/core/providers/assistant_provider.dart';

Future<AssistantProvider> _loadProvider(Assistant assistant) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'assistants_v1': Assistant.encodeList(<Assistant>[assistant]),
    'current_assistant_id_v1': assistant.id,
  });
  final provider = AssistantProvider();
  for (var attempt = 0; attempt < 50; attempt++) {
    if (provider.assistants.length == 1) return provider;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('duplicateAssistant preserves persisted character card data', () async {
    final source = Assistant(
      id: 'source',
      name: 'Character',
      characterData: AssistantCharacterData(
        cardVersion: '3.0',
        firstMes: 'Hello.',
        alternateGreetings: const <String>['Hi.', 'Welcome.'],
        cardTags: const <String>['test'],
        cardWorldBookId: 'world-book-1',
        sourceFileName: 'source.png',
        extensions: const <String, dynamic>{
          'nested': <String, dynamic>{'x': 1},
        },
        unknownFields: const <String, dynamic>{'future': true},
      ),
    );
    final provider = await _loadProvider(source);

    final duplicateId = await provider.duplicateAssistant(source.id);

    expect(duplicateId, isNotNull);
    final duplicate = provider.assistants.singleWhere(
      (assistant) => assistant.id == duplicateId,
    );
    expect(duplicate.characterData?.toJson(), source.characterData?.toJson());
  });
}

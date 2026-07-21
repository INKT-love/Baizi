import 'dart:convert';

import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/providers/chat_appearance_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stores model presentation by exact immutable model ID', () async {
    final provider = ChatAppearanceProvider();
    await provider.ready;

    await provider.setNickname('claude-opus-4-6', '白子');

    final profile = provider.profileFor('claude-opus-4-6');
    expect(profile, isNotNull);
    expect(profile!.modelId, 'claude-opus-4-6');
    expect(profile.nickname, '白子');
    expect(provider.profileFor('claude-opus-4-6-renamed'), isNull);
  });

  test(
    'persists profile map separately from model request configuration',
    () async {
      final provider = ChatAppearanceProvider();
      await provider.ready;
      await provider.setNickname('gpt-5', '小澪');
      await provider.setBackgroundMode(ChatBackgroundMode.latestAssistantReply);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('chat_appearance_profiles_v1');
      final data = jsonDecode(raw!) as Map<String, dynamic>;
      final profiles = data['profiles'] as Map<String, dynamic>;

      expect(data['backgroundMode'], 'latestAssistantReply');
      expect(profiles['gpt-5']['modelId'], 'gpt-5');
      expect(profiles['gpt-5']['nickname'], '小澪');
      expect(data.containsKey('apiModelId'), isFalse);
    },
  );

  test('loads existing appearance profiles and supports reset', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat_appearance_profiles_v1': jsonEncode(<String, dynamic>{
        'backgroundMode': 'selectedModel',
        'profiles': <String, dynamic>{
          'deepseek-v4': <String, dynamic>{
            'modelId': 'deepseek-v4',
            'nickname': '深思',
          },
        },
      }),
    });
    final provider = ChatAppearanceProvider();
    await provider.ready;

    expect(provider.profileFor('deepseek-v4')?.nickname, '深思');
    await provider.resetProfile('deepseek-v4');
    expect(provider.profileFor('deepseek-v4'), isNull);
  });
}

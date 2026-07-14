import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/secure_api_key_store.dart';
import 'package:Kelivo/features/home/controllers/chat_controller.dart';
import 'package:Kelivo/features/home/controllers/generation_controller.dart';
import 'package:Kelivo/features/home/controllers/stream_controller.dart'
    as home_stream;
import 'package:Kelivo/features/home/services/message_builder_service.dart';
import 'package:Kelivo/features/home/services/message_generation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('legacy assistant cannot disable incremental output', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'baizi_models_cache_v1': <String>['gpt-test'],
    });
    final settings = SettingsProvider(
      apiKeyStore: SecureApiKeyStore(backend: _MemorySecureApiKeyBackend()),
    );
    await settings.initialization;
    addTearDown(settings.dispose);

    late BuildContext appContext;
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              appContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final chatService = ChatService();
    final streamController = home_stream.StreamController(
      chatService: chatService,
      onStateChanged: () {},
      getSettingsProvider: () => settings,
      getCurrentConversationId: () => 'conversation-1',
    );
    final messageBuilderService = MessageBuilderService(
      chatService: chatService,
      contextProvider: appContext,
    );
    final chatController = ChatController(chatService: chatService);
    final generationController = GenerationController(
      chatService: chatService,
      chatController: chatController,
      streamController: streamController,
      messageBuilderService: messageBuilderService,
      contextProvider: appContext,
      onStateChanged: () {},
      getTitleForLocale: (_) => 'New Chat',
    );
    final service = MessageGenerationService(
      chatService: chatService,
      messageBuilderService: messageBuilderService,
      generationController: generationController,
      streamController: streamController,
      contextProvider: appContext,
    );
    addTearDown(chatController.dispose);
    addTearDown(streamController.dispose);
    addTearDown(chatService.dispose);

    final legacyAssistant = Assistant.fromJson(<String, dynamic>{
      'id': 'legacy-assistant',
      'name': 'Legacy assistant',
      'streamOutput': false,
    });
    expect(legacyAssistant.streamOutput, isFalse);

    final context = service.buildGenerationContext(
      assistantMessage: ChatMessage(
        id: 'assistant-message',
        role: 'assistant',
        content: '',
        conversationId: 'conversation-1',
        isStreaming: true,
      ),
      prepared: PreparedGeneration(
        apiMessages: const <Map<String, dynamic>>[],
        toolDefs: const <Map<String, dynamic>>[],
        hasBuiltInSearch: false,
        lastUserImagePaths: const <String>[],
      ),
      userImagePaths: const <String>[],
      allowImagesApiRouting: false,
      providerKey: 'baizi',
      modelId: 'gpt-test',
      assistant: legacyAssistant,
      settings: settings,
      supportsReasoning: true,
      enableReasoning: true,
      generateTitleOnFinish: true,
    );

    expect(context.streamOutput, isTrue);
  });
}

final class _MemorySecureApiKeyBackend implements SecureApiKeyBackend {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

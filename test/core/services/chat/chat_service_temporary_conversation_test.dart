import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Baizi/core/services/chat/chat_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';

  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'kelivo_chat_service_test_',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ChatService temporary conversations', () {
    test('ordinary draft persists when its first message is added', () async {
      final service = ChatService();
      await service.init();

      final conversation = await service.createDraftConversation(title: 'Chat');
      await service.addMessage(
        conversationId: conversation.id,
        role: 'user',
        content: 'hello',
      );

      expect(service.getAllConversations().map((c) => c.id), [conversation.id]);
      expect(service.getMessages(conversation.id), hasLength(1));
    });

    test(
      'temporary draft keeps messages in memory without entering history',
      () async {
        final service = ChatService();
        await service.init();

        final conversation = await service.createDraftConversation(
          title: 'Temporary Chat',
          temporary: true,
        );
        await service.addMessage(
          conversationId: conversation.id,
          role: 'user',
          content: 'secret',
        );

        expect(service.getAllConversations(), isEmpty);
        expect(service.getConversation(conversation.id), isNotNull);
        expect(service.getMessages(conversation.id), hasLength(1));
        expect(service.isTemporaryConversation(conversation.id), isTrue);
      },
    );

    test(
      'temporary conversation supports range and recent message reads',
      () async {
        final service = ChatService();
        await service.init();

        final conversation = await service.createDraftConversation(
          title: 'Temporary Chat',
          temporary: true,
        );
        for (var i = 0; i < 5; i++) {
          await service.addMessage(
            conversationId: conversation.id,
            role: i.isEven ? 'user' : 'assistant',
            content: 'temporary message $i',
          );
        }

        final range = service.getMessagesRange(
          conversation.id,
          start: 1,
          limit: 3,
        );
        final recent = service.getRecentMessages(
          conversation.id,
          minMessages: 2,
          maxMessages: 2,
        );

        expect(range.map((message) => message.content), [
          'temporary message 1',
          'temporary message 2',
          'temporary message 3',
        ]);
        expect(recent.map((message) => message.content), [
          'temporary message 3',
          'temporary message 4',
        ]);
      },
    );

    test(
      'temporary conversation is discarded when current conversation changes',
      () async {
        final service = ChatService();
        await service.init();

        final temporary = await service.createDraftConversation(
          title: 'Temporary Chat',
          temporary: true,
        );
        await service.addMessage(
          conversationId: temporary.id,
          role: 'user',
          content: 'secret',
        );

        final ordinary = await service.createDraftConversation(title: 'Chat');

        expect(service.getConversation(temporary.id), isNull);
        expect(service.getMessages(temporary.id), isEmpty);
        expect(service.currentConversationId, ordinary.id);
        expect(service.getAllConversations(), isEmpty);
      },
    );

    test('temporary message deletion only affects memory', () async {
      final service = ChatService();
      await service.init();

      final conversation = await service.createDraftConversation(
        title: 'Temporary Chat',
        temporary: true,
      );
      final message = await service.addMessage(
        conversationId: conversation.id,
        role: 'user',
        content: 'secret',
      );

      await service.deleteMessage(message.id);

      expect(service.getAllConversations(), isEmpty);
      expect(service.getMessages(conversation.id), isEmpty);
      expect(service.getConversation(conversation.id)?.messageIds, isEmpty);
    });
  });

  group('ChatService character greetings', () {
    test(
      'stores alternate greetings as versions with the default selected',
      () async {
        final service = ChatService();
        await service.init();

        final conversation = await service.createDraftConversation(
          title: 'Character Chat',
          assistantId: 'character-1',
        );
        final greeting = await service.initializeCharacterGreeting(
          conversationId: conversation.id,
          firstMessage: 'Default greeting',
          alternateGreetings: const <String>['Alternate one', 'Alternate two'],
        );

        final messages = service.getMessages(conversation.id);
        expect(greeting, isNotNull);
        expect(
          messages.map((message) => message.role),
          everyElement('assistant'),
        );
        expect(messages.map((message) => message.content), <String>[
          'Default greeting',
          'Alternate one',
          'Alternate two',
        ]);
        expect(messages.map((message) => message.groupId).toSet(), <String?>{
          greeting!.groupId,
        });
        expect(messages.map((message) => message.version), <int>[0, 1, 2]);
        expect(service.getVersionSelections(conversation.id), <String, int>{
          greeting.groupId!: 0,
        });
        expect(
          service.hasOnlyCharacterGreetingMessages(conversation.id),
          isTrue,
        );

        await service.addMessage(
          conversationId: conversation.id,
          role: 'user',
          content: 'Hello',
        );

        expect(
          service.hasOnlyCharacterGreetingMessages(conversation.id),
          isFalse,
        );
      },
    );

    test(
      'initialization is idempotent concurrently and after reopening',
      () async {
        final service = ChatService();
        await service.init();

        final conversation = await service.createDraftConversation(
          title: 'Character Chat',
          assistantId: 'character-1',
        );
        final results = await Future.wait([
          service.initializeCharacterGreeting(
            conversationId: conversation.id,
            firstMessage: 'Default greeting',
            alternateGreetings: const <String>['Alternate'],
          ),
          service.initializeCharacterGreeting(
            conversationId: conversation.id,
            firstMessage: 'Default greeting',
            alternateGreetings: const <String>['Alternate'],
          ),
        ]);

        expect(results[0]?.id, results[1]?.id);
        expect(service.getMessages(conversation.id), hasLength(2));

        await Hive.close();
        final reopened = ChatService();
        await reopened.init();
        final reopenedGreeting = await reopened.initializeCharacterGreeting(
          conversationId: conversation.id,
          firstMessage: 'A replacement must not be inserted',
          alternateGreetings: const <String>['Another replacement'],
        );

        expect(reopenedGreeting?.id, results.first?.id);
        expect(
          reopened
              .getMessages(conversation.id)
              .map((message) => message.content),
          <String>['Default greeting', 'Alternate'],
        );
      },
    );

    test('temporary conversation keeps greeting versions in memory', () async {
      final service = ChatService();
      await service.init();

      final conversation = await service.createDraftConversation(
        title: 'Temporary Character Chat',
        assistantId: 'character-1',
        temporary: true,
      );
      final greeting = await service.initializeCharacterGreeting(
        conversationId: conversation.id,
        firstMessage: 'Default greeting',
        alternateGreetings: const <String>['Alternate'],
      );

      final messages = service.getMessages(conversation.id);
      expect(service.getAllConversations(), isEmpty);
      expect(service.isTemporaryConversation(conversation.id), isTrue);
      expect(messages.map((message) => message.content), <String>[
        'Default greeting',
        'Alternate',
      ]);
      expect(messages.map((message) => message.version), <int>[0, 1]);
      expect(service.getVersionSelections(conversation.id), <String, int>{
        greeting!.groupId!: 0,
      });
      expect(service.hasOnlyCharacterGreetingMessages(conversation.id), isTrue);
    });

    test('empty first message does not insert alternate greetings', () async {
      final service = ChatService();
      await service.init();

      final conversation = await service.createDraftConversation(
        title: 'Character Chat',
        assistantId: 'character-1',
      );
      final greeting = await service.initializeCharacterGreeting(
        conversationId: conversation.id,
        firstMessage: '   ',
        alternateGreetings: const <String>['Alternate'],
      );

      expect(greeting, isNull);
      expect(service.getMessages(conversation.id), isEmpty);
      expect(service.getAllConversations(), isEmpty);
    });
  });

  group('ChatService fork conversations', () {
    test(
      'fork copies selected path as plain single-version messages',
      () async {
        final service = ChatService();
        await service.init();

        final source = await service.createConversation(title: 'Source');
        final original = await service.addMessage(
          conversationId: source.id,
          role: 'assistant',
          content: 'original answer',
        );
        final edited = await service.appendMessageVersion(
          messageId: original.id,
          content: 'edited answer',
        );
        expect(edited, isNotNull);

        final fork = await service.forkConversation(
          title: 'Fork',
          assistantId: null,
          sourceMessages: [edited!],
        );

        final forkMessages = service.getMessages(fork.id);
        expect(forkMessages, hasLength(1));
        expect(forkMessages.single.conversationId, fork.id);
        expect(forkMessages.single.content, 'edited answer');
        expect(
          forkMessages.single.groupId ?? forkMessages.single.id,
          forkMessages.single.id,
        );
        expect(forkMessages.single.version, 0);
        expect(service.getVersionSelections(fork.id), isEmpty);
      },
    );
  });
}

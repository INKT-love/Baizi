import '../models/menstrual_care.dart';
import '../providers/settings_provider.dart';
import 'api/chat_api_service.dart';
import 'chat/chat_service.dart';
import 'menstrual_care_proactive_logic.dart';
import 'menstrual_care_proactive_scheduler.dart';
import 'menstrual_care_prompt_context.dart';
import 'menstrual_care_store.dart';
import 'menstrual_care_calculator.dart';

class MenstrualCareProactiveService {
  MenstrualCareProactiveService({MenstrualCareStore? store})
    : _store = store ?? MenstrualCareStore();

  final MenstrualCareStore _store;

  Future<void> runFromBackground() async {
    final profile = await _store.read();
    final decision = MenstrualCareProactiveLogic.evaluate(
      profile,
      now: DateTime.now(),
    );
    if (!decision.shouldRun || profile == null) {
      await MenstrualCareProactiveScheduler().reschedule(profile);
      return;
    }
    final today = dayOnly(DateTime.now()).toIso8601String();
    await _store.write(profile.copyWith(proactiveCareLastAttemptDay: today));
    try {
      final settings = SettingsProvider();
      await settings.initialization;
      final modelId = settings.currentModelId;
      if (modelId == null || modelId.isEmpty) {
        throw StateError('No selected model');
      }
      final chatService = ChatService();
      await chatService.init();
      final destination = await _resolveDestination(chatService, profile);
      if (destination == null) throw StateError('No eligible conversation');
      final context = MenstrualCarePromptContext.build(
        profile,
        MenstrualCareCalculator.calculate(profile),
      );
      final request = decision.isExpectedEndDay
          ? '这是一次主动经期关怀。今天是预计结束日。请用当前对话的自然语气，简短、体贴地询问用户这次经期是否结束、身体是否还不舒服；不要假定已经结束，不作诊断。'
          : '这是一次主动经期关怀。请用当前对话的自然语气，写一句不重复、简短且体贴的关心，可询问今天是否痛经或是否需要休息建议；不要作诊断。';
      final content = StringBuffer();
      await for (final chunk in ChatApiService.sendMessageStream(
        config: settings.baiziProviderConfig,
        modelId: modelId,
        messages: <Map<String, dynamic>>[
          {'role': 'system', 'content': context ?? ''},
          {'role': 'user', 'content': request},
        ],
        tools: const [],
        stream: true,
        requestId: 'menstrual-care-$today',
      )) {
        content.write(chunk.content);
      }
      final reply = content.toString().trim();
      if (reply.isEmpty) throw StateError('Empty proactive reply');
      await chatService.addMessage(
        conversationId: destination.id,
        role: 'assistant',
        content: reply,
        modelId: modelId,
        providerId: settings.currentModelProvider,
      );
      await _store.write(
        profile.copyWith(
          proactiveCareLastAttemptDay: today,
          proactiveCareLastSuccessDay: today,
          clearProactiveCareLastError: true,
        ),
      );
    } catch (error) {
      final current = await _store.read();
      if (current != null) {
        await _store.write(
          current.copyWith(
            proactiveCareLastAttemptDay: today,
            proactiveCareLastError: error.runtimeType.toString(),
          ),
        );
      }
    } finally {
      await MenstrualCareProactiveScheduler().reschedule(await _store.read());
    }
  }

  Future<dynamic> _resolveDestination(
    ChatService chatService,
    MenstrualCareProfile profile,
  ) async {
    if (profile.proactiveCareDestination ==
        MenstrualCareDestination.dedicatedConversation) {
      final id = profile.proactiveCareConversationId;
      if (id != null) return chatService.getConversation(id);
      final conversation = await chatService.createConversation(title: '经期关怀');
      await _store.write(
        profile.copyWith(proactiveCareConversationId: conversation.id),
      );
      return conversation;
    }
    final conversations = chatService.getAllConversations();
    return conversations.isEmpty ? null : conversations.first;
  }
}

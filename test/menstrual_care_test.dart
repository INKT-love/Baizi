import 'package:flutter_test/flutter_test.dart';
import '../lib/core/models/menstrual_care.dart';
import '../lib/core/services/menstrual_care_calculator.dart';
import '../lib/core/services/menstrual_care_message_recognizer.dart';
import '../lib/core/services/menstrual_care_prompt_context.dart';
import '../lib/core/services/menstrual_care_proactive_logic.dart';
import '../lib/core/providers/menstrual_care_provider.dart';
import '../lib/core/services/menstrual_care_store.dart';
import '../lib/core/services/menstrual_reminder_scheduler.dart';

class _MemoryStore extends MenstrualCareStore {
  MenstrualCareProfile? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<MenstrualCareProfile?> read() async => value;

  @override
  Future<void> write(MenstrualCareProfile next) async => value = next;
}

class _NoopScheduler extends MenstrualReminderScheduler {
  @override
  Future<void> reschedule(MenstrualCareProfile? profile) async {}
}

void main() {
  final profile = MenstrualCareProfile(
    lastStartDate: DateTime(2026, 7, 1),
    cycleDays: 28,
    periodDays: 5,
  );

  test('calculates period and delayed phases locally', () {
    expect(
      MenstrualCareCalculator.calculate(
        profile,
        now: DateTime(2026, 7, 29),
      ).phase,
      MenstrualPhase.expectedStart,
    );
    expect(
      MenstrualCareCalculator.calculate(
        profile,
        now: DateTime(2026, 7, 3),
      ).phase,
      MenstrualPhase.period,
    );
    expect(
      MenstrualCareCalculator.calculate(
        profile,
        now: DateTime(2026, 7, 30),
      ).phase,
      MenstrualPhase.delayed,
    );
  });

  test(
    'prompt context includes the authorized cycle dates for direct answers',
    () {
      final status = MenstrualCareCalculator.calculate(
        profile,
        now: DateTime(2026, 7, 3),
      );
      final prompt = MenstrualCarePromptContext.build(profile, status)!;
      expect(prompt, contains('2026-07-01'));
      expect(prompt, contains('2026-07-29'));
      expect(prompt, contains('必须直接依据上述数据回答'));
      expect(prompt, contains('保持当前角色人设'));
    },
  );

  test('proactive care runs once daily during a period and flags end day', () {
    final active = MenstrualCareProfile(
      lastStartDate: DateTime(2026, 7, 1),
      periodDays: 3,
      proactiveCareEnabled: true,
      proactiveCareMinutes: 9 * 60,
      records: [MenstrualCycleRecord(startDate: DateTime(2026, 7, 1))],
    );
    final firstDay = MenstrualCareProactiveLogic.evaluate(
      active,
      now: DateTime(2026, 7, 1, 9),
    );
    expect(firstDay.shouldRun, isTrue);
    expect(firstDay.blockReason, isNull);
    expect(firstDay.isExpectedEndDay, isFalse);
    final endDay = MenstrualCareProactiveLogic.evaluate(
      active,
      now: DateTime(2026, 7, 3, 9),
    );
    expect(endDay.shouldRun, isTrue);
    expect(endDay.isExpectedEndDay, isTrue);
    expect(
      MenstrualCareProactiveLogic.evaluate(
        active.copyWith(proactiveCareLastAttemptDay: '2026-07-01T00:00:00.000'),
        now: DateTime(2026, 7, 1, 10),
      ).shouldRun,
      isFalse,
    );
    expect(
      MenstrualCareProactiveLogic.evaluate(
        active.copyWith(
          proactiveCareLastAttemptDay: '2026-07-01T00:00:00.000',
          proactiveCareLastError: '网络暂时不可用',
        ),
        now: DateTime(2026, 7, 1, 10),
      ).shouldRun,
      isTrue,
    );
    final alreadySent = MenstrualCareProactiveLogic.evaluate(
      active.copyWith(proactiveCareLastSuccessDay: '2026-07-01T00:00:00.000'),
      now: DateTime(2026, 7, 1, 10),
    );
    expect(alreadySent.shouldRun, isFalse);
    expect(
      alreadySent.blockReason,
      MenstrualCareProactiveBlockReason.alreadySentToday,
    );
    final debugRetry = MenstrualCareProactiveLogic.evaluate(
      active.copyWith(proactiveCareLastSuccessDay: '2026-07-01T00:00:00.000'),
      now: DateTime(2026, 7, 1, 10),
      ignoreDailyLimit: true,
    );
    expect(debugRetry.shouldRun, isTrue);
  });

  test('proactive care catches up after its configured time', () {
    final active = MenstrualCareProfile(
      lastStartDate: DateTime(2026, 7, 1),
      periodDays: 3,
      proactiveCareEnabled: true,
      proactiveCareMinutes: 9 * 60,
      records: [MenstrualCycleRecord(startDate: DateTime(2026, 7, 1))],
    );
    expect(
      MenstrualCareProactiveLogic.evaluate(
        active,
        now: DateTime(2026, 7, 1, 17, 30),
      ).shouldRun,
      isTrue,
    );
  });

  test('recognizer only accepts explicit first-person statements', () {
    expect(
      MenstrualCareMessageRecognizer.recognize('我今天来月经了'),
      MenstrualRecordIntent.start,
    );
    expect(
      MenstrualCareMessageRecognizer.recognize('她今天来月经了'),
      MenstrualRecordIntent.none,
    );
    expect(
      MenstrualCareMessageRecognizer.recognize('“我今天来月经了”是角色台词'),
      MenstrualRecordIntent.none,
    );
    expect(
      MenstrualCareMessageRecognizer.recognize('我今天月经开始了'),
      MenstrualRecordIntent.start,
    );
    expect(
      MenstrualCareMessageRecognizer.recognize('我姨妈结束了'),
      MenstrualRecordIntent.end,
    );
    expect(
      MenstrualCareMessageRecognizer.recognize('她今天月经来了'),
      MenstrualRecordIntent.none,
    );
  });

  test(
    'manual end reports whether an open record exists and reset clears data',
    () async {
      final store = _MemoryStore();
      final provider = MenstrualCareProvider(
        store: store,
        scheduler: _NoopScheduler(),
      );
      await provider.load();
      await provider.configure(
        lastStartDate: DateTime(2026, 7, 1),
        cycleDays: 28,
        periodDays: 5,
      );
      expect(await provider.recordEnd(DateTime(2026, 7, 5)), isTrue);
      expect(await provider.recordEnd(DateTime(2026, 7, 5)), isFalse);
      await provider.clear();
      expect(provider.profile, isNull);
      expect(store.value, isNull);
    },
  );

  test('refreshes profile changed by the background isolate', () async {
    final store = _MemoryStore()
      ..value = MenstrualCareProfile(
        lastStartDate: DateTime(2026, 7, 1),
        records: [MenstrualCycleRecord(startDate: DateTime(2026, 7, 1))],
      );
    final provider = MenstrualCareProvider(
      store: store,
      scheduler: _NoopScheduler(),
    );
    await provider.load();

    store.value = store.value!.copyWith(
      proactiveCareLastSuccessDay: '2026-07-03T00:00:00.000',
    );
    await provider.refreshProfileFromStore();

    expect(
      provider.profile!.proactiveCareLastSuccessDay,
      '2026-07-03T00:00:00.000',
    );
    provider.dispose();
  });
}

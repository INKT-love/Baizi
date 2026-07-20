import 'package:flutter_test/flutter_test.dart';
import '../lib/core/models/menstrual_care.dart';
import '../lib/core/services/menstrual_care_calculator.dart';
import '../lib/core/services/menstrual_care_message_recognizer.dart';
import '../lib/core/services/menstrual_care_prompt_context.dart';

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

  test('prompt context contains no exact local dates', () {
    final status = MenstrualCareCalculator.calculate(
      profile,
      now: DateTime(2026, 7, 3),
    );
    final prompt = MenstrualCarePromptContext.build(status)!;
    expect(prompt, isNot(contains('2026-07-01')));
    expect(prompt, contains('保持当前角色人设'));
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
  });
}

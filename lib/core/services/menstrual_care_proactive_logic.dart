import '../models/menstrual_care.dart';
import 'menstrual_care_calculator.dart';

class MenstrualCareProactiveDecision {
  const MenstrualCareProactiveDecision({
    required this.shouldRun,
    required this.isExpectedEndDay,
  });

  final bool shouldRun;
  final bool isExpectedEndDay;
}

class MenstrualCareProactiveLogic {
  static MenstrualCareProactiveDecision evaluate(
    MenstrualCareProfile? profile, {
    required DateTime now,
    bool ignoreTime = false,
  }) {
    if (profile == null || !profile.proactiveCareEnabled) {
      return const MenstrualCareProactiveDecision(
        shouldRun: false,
        isExpectedEndDay: false,
      );
    }
    final today = dayOnly(now);
    final lastRecord = _latestRecord(profile);
    if (lastRecord == null || lastRecord.endDate != null) {
      return const MenstrualCareProactiveDecision(
        shouldRun: false,
        isExpectedEndDay: false,
      );
    }
    final start = dayOnly(lastRecord.startDate);
    final dayNumber = today.difference(start).inDays + 1;
    if (dayNumber < 1 || dayNumber > profile.periodDays) {
      return const MenstrualCareProactiveDecision(
        shouldRun: false,
        isExpectedEndDay: false,
      );
    }
    final todayKey = today.toIso8601String();
    if (profile.proactiveCareLastAttemptDay == todayKey) {
      return const MenstrualCareProactiveDecision(
        shouldRun: false,
        isExpectedEndDay: false,
      );
    }
    final scheduledMinutes = profile.proactiveCareMinutes;
    final currentMinutes = now.hour * 60 + now.minute;
    if (!ignoreTime && currentMinutes < scheduledMinutes) {
      return const MenstrualCareProactiveDecision(
        shouldRun: false,
        isExpectedEndDay: false,
      );
    }
    return MenstrualCareProactiveDecision(
      shouldRun: true,
      isExpectedEndDay: dayNumber == profile.periodDays,
    );
  }

  static MenstrualCycleRecord? _latestRecord(MenstrualCareProfile profile) {
    MenstrualCycleRecord? latest;
    for (final record in profile.records) {
      if (latest == null || record.startDate.isAfter(latest.startDate)) {
        latest = record;
      }
    }
    return latest;
  }
}

import '../models/menstrual_care.dart';

enum MenstrualCareProactiveBlockReason {
  disabled,
  noActivePeriod,
  alreadySentToday,
  alreadyAttemptedToday,
  beforeScheduledTime,
}

class MenstrualCareProactiveDecision {
  const MenstrualCareProactiveDecision({
    required this.shouldRun,
    required this.isExpectedEndDay,
    this.blockReason,
  });

  final bool shouldRun;
  final bool isExpectedEndDay;
  final MenstrualCareProactiveBlockReason? blockReason;
}

class MenstrualCareProactiveLogic {
  static MenstrualCareProactiveDecision evaluate(
    MenstrualCareProfile? profile, {
    required DateTime now,
    bool ignoreTime = false,
    bool ignoreDailyLimit = false,
  }) {
    if (profile == null || !profile.proactiveCareEnabled) {
      return const MenstrualCareProactiveDecision(
        shouldRun: false,
        isExpectedEndDay: false,
        blockReason: MenstrualCareProactiveBlockReason.disabled,
      );
    }
    final today = dayOnly(now);
    final lastRecord = _latestRecord(profile);
    if (lastRecord == null || lastRecord.endDate != null) {
      return const MenstrualCareProactiveDecision(
        shouldRun: false,
        isExpectedEndDay: false,
        blockReason: MenstrualCareProactiveBlockReason.noActivePeriod,
      );
    }
    final start = dayOnly(lastRecord.startDate);
    final dayNumber = today.difference(start).inDays + 1;
    if (dayNumber < 1 || dayNumber > profile.periodDays) {
      return const MenstrualCareProactiveDecision(
        shouldRun: false,
        isExpectedEndDay: false,
        blockReason: MenstrualCareProactiveBlockReason.noActivePeriod,
      );
    }
    final todayKey = today.toIso8601String();
    // A successful message is sent at most once per day. Failed attempts keep
    // their error marker so the foreground timer and WorkManager can retry.
    if (!ignoreDailyLimit && profile.proactiveCareLastSuccessDay == todayKey) {
      return const MenstrualCareProactiveDecision(
        shouldRun: false,
        isExpectedEndDay: false,
        blockReason: MenstrualCareProactiveBlockReason.alreadySentToday,
      );
    }
    if (!ignoreDailyLimit &&
        profile.proactiveCareLastAttemptDay == todayKey &&
        profile.proactiveCareLastError == null) {
      return const MenstrualCareProactiveDecision(
        shouldRun: false,
        isExpectedEndDay: false,
        blockReason: MenstrualCareProactiveBlockReason.alreadyAttemptedToday,
      );
    }
    final scheduledMinutes = profile.proactiveCareMinutes;
    final currentMinutes = now.hour * 60 + now.minute;
    if (!ignoreTime && currentMinutes < scheduledMinutes) {
      return const MenstrualCareProactiveDecision(
        shouldRun: false,
        isExpectedEndDay: false,
        blockReason: MenstrualCareProactiveBlockReason.beforeScheduledTime,
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

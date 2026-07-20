import '../models/menstrual_care.dart';

class MenstrualCareCalculator {
  static MenstrualStatus calculate(
    MenstrualCareProfile profile, {
    DateTime? now,
  }) {
    final today = dayOnly(now ?? DateTime.now());
    final starts = <DateTime>[
      profile.lastStartDate,
      ...profile.records.map((e) => e.startDate),
    ]..sort();
    final anchor = dayOnly(starts.last);
    final effectiveCycle = _effectiveCycle(starts, profile.cycleDays);
    final cycleDay = today.difference(anchor).inDays + 1;
    final expectedStart = anchor.add(Duration(days: effectiveCycle));
    final expectedEnd = anchor.add(Duration(days: profile.periodDays - 1));
    final irregular =
        starts.length > 1 &&
        (starts.last.difference(starts[starts.length - 2]).inDays -
                    profile.cycleDays)
                .abs() >=
            7;
    MenstrualPhase phase;
    if (cycleDay <= 0)
      phase = MenstrualPhase.unknown;
    else if (cycleDay <= profile.periodDays)
      phase = MenstrualPhase.period;
    else if (cycleDay == effectiveCycle)
      phase = MenstrualPhase.expectedStart;
    else if (cycleDay > effectiveCycle)
      phase = MenstrualPhase.delayed;
    else if ((cycleDay - (effectiveCycle ~/ 2)).abs() <= 2)
      phase = MenstrualPhase.ovulationWindow;
    else if (cycleDay >= effectiveCycle - 5)
      phase = MenstrualPhase.prePeriod;
    else
      phase = MenstrualPhase.postPeriod;
    return MenstrualStatus(
      phase: phase,
      cycleDay: cycleDay,
      expectedStartDate: expectedStart,
      expectedEndDate: expectedEnd,
      irregular: irregular,
    );
  }

  static int _effectiveCycle(List<DateTime> starts, int fallback) {
    if (starts.length < 3) return fallback.clamp(21, 45).toInt();
    final durations = <int>[];
    for (var i = 1; i < starts.length; i++) {
      final days = starts[i].difference(starts[i - 1]).inDays;
      if (days >= 21 && days <= 45) durations.add(days);
    }
    if (durations.isEmpty) return fallback.clamp(21, 45).toInt();
    return (durations.reduce((a, b) => a + b) / durations.length).round();
  }
}

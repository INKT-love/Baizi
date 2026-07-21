import 'dart:io' show Platform;

import 'package:workmanager/workmanager.dart';

import '../models/menstrual_care.dart';
import 'menstrual_care_proactive_service.dart';
import 'menstrual_care_store.dart';

class MenstrualCareProactiveScheduler {
  static const taskName = 'baizi_menstrual_care_daily';
  static const uniqueName = 'baizi_menstrual_care_daily_v1';

  Future<void> reschedule(MenstrualCareProfile? profile) async {
    if (!Platform.isAndroid) return;
    await Workmanager().cancelByUniqueName(uniqueName);
    if (profile == null || !profile.proactiveCareEnabled) return;
    final now = DateTime.now();
    final minutes = profile.proactiveCareMinutes.clamp(0, 1439).toInt();
    var next = DateTime(
      now.year,
      now.month,
      now.day,
      minutes ~/ 60,
      minutes % 60,
    );
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    await Workmanager().registerOneOffTask(
      uniqueName,
      taskName,
      initialDelay: next.difference(now),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: profile.proactiveCareAllowMobileData
            ? NetworkType.connected
            : NetworkType.unmetered,
      ),
      // A failed request should be retried during the current day instead of
      // silently waiting until tomorrow's scheduled task.
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
  }
}

@pragma('vm:entry-point')
void menstrualCareCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != MenstrualCareProactiveScheduler.taskName) return true;
    final outcome = await MenstrualCareProactiveService().runIfDue();
    if (outcome == MenstrualCareProactiveOutcome.failed) {
      // Returning false asks Android WorkManager to use the configured backoff.
      return false;
    }
    await MenstrualCareProactiveScheduler().reschedule(
      await MenstrualCareStore().read(),
    );
    return true;
  });
}

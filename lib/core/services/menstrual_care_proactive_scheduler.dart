import 'dart:io' show Platform;

import 'package:workmanager/workmanager.dart';

import '../models/menstrual_care.dart';
import 'menstrual_care_proactive_service.dart';

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
    );
  }
}

@pragma('vm:entry-point')
void menstrualCareCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != MenstrualCareProactiveScheduler.taskName) return true;
    try {
      await MenstrualCareProactiveService().runFromBackground();
    } catch (_) {
      // The service persists a local error; returning success prevents retries.
    }
    return true;
  });
}

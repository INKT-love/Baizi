import '../models/menstrual_care.dart';
import 'menstrual_care_calculator.dart';
import 'notification_service.dart';

class MenstrualReminderScheduler {
  Future<void> reschedule(MenstrualCareProfile? profile) async {
    await NotificationService.cancelPrivateCareReminders();
    if (profile == null || !profile.remindersEnabled) return;
    if (!await NotificationService.ensureAndroidNotificationsPermission())
      return;
    final status = MenstrualCareCalculator.calculate(profile);
    final time = profile.reminderMinutes.clamp(0, 1439).toInt();
    DateTime at(DateTime day) =>
        DateTime(day.year, day.month, day.day, time ~/ 60, time % 60);
    final entries = <int, DateTime>{
      4101: at(
        status.expectedStartDate.subtract(
          Duration(days: profile.advanceReminderDays),
        ),
      ),
      4102: at(status.expectedStartDate),
      4103: at(status.expectedEndDate),
      4104: at(status.expectedStartDate.add(const Duration(days: 3))),
    };
    for (final entry in entries.entries) {
      await NotificationService.schedulePrivateCareReminder(
        id: entry.key,
        when: entry.value,
      );
    }
  }
}

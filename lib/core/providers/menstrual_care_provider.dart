import 'package:flutter/foundation.dart';
import '../models/menstrual_care.dart';
import '../services/menstrual_care_calculator.dart';
import '../services/menstrual_care_store.dart';
import '../services/menstrual_reminder_scheduler.dart';

class MenstrualCareProvider extends ChangeNotifier {
  MenstrualCareProvider({
    MenstrualCareStore? store,
    MenstrualReminderScheduler? scheduler,
  }) : _store = store ?? MenstrualCareStore(),
       _scheduler = scheduler ?? MenstrualReminderScheduler() {
    load();
  }
  final MenstrualCareStore _store;
  final MenstrualReminderScheduler _scheduler;
  MenstrualCareProfile? _profile;
  bool _loaded = false;
  bool get loaded => _loaded;
  MenstrualCareProfile? get profile => _profile;
  bool get isConfigured => _profile != null;
  MenstrualStatus? get status =>
      _profile == null ? null : MenstrualCareCalculator.calculate(_profile!);
  bool enabledForConversation(String? id) =>
      _profile?.contextEnabled == true &&
      (id == null || !_profile!.disabledConversationIds.contains(id));

  Future<void> load() async {
    try {
      _profile = await _store.read();
    } catch (_) {
      _profile = null;
    }
    _loaded = true;
    await _scheduler.reschedule(_profile);
    notifyListeners();
  }

  Future<void> configure({
    required DateTime lastStartDate,
    required int cycleDays,
    required int periodDays,
  }) async {
    if (cycleDays < 21 || cycleDays > 45 || periodDays < 1 || periodDays > 14)
      throw ArgumentError('Invalid menstrual cycle settings');
    await _save(
      MenstrualCareProfile(
        lastStartDate: dayOnly(lastStartDate),
        cycleDays: cycleDays,
        periodDays: periodDays,
        records: [MenstrualCycleRecord(startDate: dayOnly(lastStartDate))],
      ),
    );
  }

  Future<void> updateSettings({
    bool? contextEnabled,
    bool? remindersEnabled,
    bool? autoRecordEnabled,
    int? reminderMinutes,
    int? advanceReminderDays,
  }) async {
    final p = _required;
    await _save(
      p.copyWith(
        contextEnabled: contextEnabled,
        remindersEnabled: remindersEnabled,
        autoRecordEnabled: autoRecordEnabled,
        reminderMinutes: reminderMinutes,
        advanceReminderDays: advanceReminderDays,
      ),
    );
  }

  Future<void> setConversationEnabled(String id, bool enabled) async {
    final p = _required;
    final disabled = p.disabledConversationIds.toSet();
    if (enabled) {
      disabled.remove(id);
    } else {
      disabled.add(id);
    }
    await _save(p.copyWith(disabledConversationIds: disabled.toList()));
  }

  Future<void> recordStart(DateTime date, {bool automatic = false}) async {
    final p = _required;
    final day = dayOnly(date);
    final records = [
      ...p.records.where((e) => !dayOnly(e.startDate).isAtSameMomentAs(day)),
      MenstrualCycleRecord(startDate: day, automatic: automatic),
    ]..sort((a, b) => a.startDate.compareTo(b.startDate));
    await _save(p.copyWith(lastStartDate: day, records: records));
  }

  Future<void> recordEnd(DateTime date, {bool automatic = false}) async {
    final p = _required;
    final day = dayOnly(date);
    final records = [...p.records];
    final index = records.lastIndexWhere(
      (r) => !r.startDate.isAfter(day) && r.endDate == null,
    );
    if (index < 0) return;
    final item = records[index];
    records[index] = MenstrualCycleRecord(
      startDate: item.startDate,
      endDate: day,
      automatic: automatic,
    );
    await _save(p.copyWith(records: records));
  }

  Future<void> clear() async {
    await _store.clear();
    _profile = null;
    await _scheduler.reschedule(null);
    notifyListeners();
  }

  MenstrualCareProfile get _required =>
      _profile ?? (throw StateError('Menstrual care is not configured'));
  Future<void> _save(MenstrualCareProfile value) async {
    _profile = value;
    await _store.write(value);
    await _scheduler.reschedule(value);
    notifyListeners();
  }
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import '../models/menstrual_care.dart';
import '../services/menstrual_care_calculator.dart';
import '../services/menstrual_care_proactive_service.dart';
import '../services/menstrual_care_store.dart';
import '../services/chat/chat_service.dart';
import '../services/menstrual_reminder_scheduler.dart';
import '../services/menstrual_care_proactive_scheduler.dart';

class MenstrualCareProvider extends ChangeNotifier with WidgetsBindingObserver {
  MenstrualCareProvider({
    MenstrualCareStore? store,
    MenstrualReminderScheduler? scheduler,
    ChatService? chatService,
  }) : _store = store ?? MenstrualCareStore(),
       _scheduler = scheduler ?? MenstrualReminderScheduler() {
    _proactiveService = MenstrualCareProactiveService(
      chatService: chatService,
    );
    WidgetsFlutterBinding.ensureInitialized().addObserver(this);
    load();
  }
  final MenstrualCareStore _store;
  final MenstrualReminderScheduler _scheduler;
  final MenstrualCareProactiveScheduler _proactiveScheduler =
      MenstrualCareProactiveScheduler();
  late final MenstrualCareProactiveService _proactiveService;
  MenstrualCareProfile? _profile;
  Timer? _proactiveTimer;
  bool _proactiveRunInFlight = false;
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
    try {
      await _scheduler.reschedule(_profile);
    } catch (_) {
      // Reminder scheduling must never prevent private data from loading.
    }
    await _refreshProactiveCareSchedule(catchUp: true);
    notifyListeners();
  }

  Future<void> configure({
    required DateTime lastStartDate,
    required int cycleDays,
    required int periodDays,
  }) async {
    if (cycleDays < 21 || cycleDays > 45 || periodDays < 1 || periodDays > 14) {
      throw ArgumentError('Invalid menstrual cycle settings');
    }
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

  Future<void> updateProactiveCare({
    bool? enabled,
    int? minutesOfDay,
    MenstrualCareDestination? destination,
    bool? allowMobileData,
    String? conversationId,
    bool clearConversationId = false,
  }) async {
    final profile = _required;
    final minutes = minutesOfDay ?? profile.proactiveCareMinutes;
    if (minutes < 0 || minutes >= 24 * 60) {
      throw ArgumentError.value(minutes, 'minutesOfDay');
    }
    await _save(
      profile.copyWith(
        proactiveCareEnabled: enabled,
        proactiveCareMinutes: minutes,
        proactiveCareDestination: destination,
        proactiveCareAllowMobileData: allowMobileData,
        proactiveCareConversationId: conversationId,
        clearProactiveCareConversationId: clearConversationId,
      ),
    );
  }

  Future<void> recordProactiveCareAttempt({
    required DateTime now,
    required bool success,
    String? error,
  }) async {
    final profile = _required;
    final day = dayOnly(now).toIso8601String();
    await _save(
      profile.copyWith(
        proactiveCareLastAttemptDay: day,
        proactiveCareLastSuccessDay: success
            ? day
            : profile.proactiveCareLastSuccessDay,
        proactiveCareLastError: error,
        clearProactiveCareLastError: success,
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

  Future<bool> recordEnd(DateTime date, {bool automatic = false}) async {
    final p = _required;
    final day = dayOnly(date);
    final records = [...p.records];
    final index = records.lastIndexWhere(
      (r) => !r.startDate.isAfter(day) && r.endDate == null,
    );
    if (index < 0) return false;
    final item = records[index];
    records[index] = MenstrualCycleRecord(
      startDate: item.startDate,
      endDate: day,
      automatic: automatic,
    );
    await _save(p.copyWith(records: records));
    return true;
  }

  Future<void> clear() async {
    await _store.clear();
    _profile = null;
    try {
      await _scheduler.reschedule(null);
    } catch (_) {}
    await _refreshProactiveCareSchedule();
    notifyListeners();
  }

  MenstrualCareProfile get _required =>
      _profile ?? (throw StateError('Menstrual care is not configured'));
  Future<void> _save(MenstrualCareProfile value) async {
    _profile = value;
    await _store.write(value);
    notifyListeners();
    try {
      await _scheduler.reschedule(value);
    } catch (_) {
      // The saved cycle remains usable when notification permission/API fails.
    }
    await _refreshProactiveCareSchedule(catchUp: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_runProactiveCareIfDue());
    }
  }

  Future<void> _refreshProactiveCareSchedule({bool catchUp = false}) async {
    final profile = _profile;
    try {
      await _proactiveScheduler.reschedule(profile);
    } catch (_) {
      // The foreground timer below still covers an active app session.
    }
    _scheduleForegroundCare(profile);
    if (catchUp) unawaited(_runProactiveCareIfDue());
  }

  void _scheduleForegroundCare(MenstrualCareProfile? profile) {
    _proactiveTimer?.cancel();
    _proactiveTimer = null;
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
    _proactiveTimer = Timer(next.difference(now), () {
      unawaited(_runProactiveCareIfDue());
    });
  }

  Future<void> _runProactiveCareIfDue() async {
    if (_proactiveRunInFlight || _profile?.proactiveCareEnabled != true) return;
    _proactiveRunInFlight = true;
    try {
      final outcome = await _proactiveService.runIfDue();
      _profile = await _store.read();
      notifyListeners();
      if (outcome == MenstrualCareProactiveOutcome.failed) {
        // Keep an active app useful after a transient network failure. Android
        // WorkManager performs the equivalent retry while in the background.
        _proactiveTimer?.cancel();
        _proactiveTimer = Timer(const Duration(minutes: 15), () {
          unawaited(_runProactiveCareIfDue());
        });
      } else {
        await _refreshProactiveCareSchedule();
      }
    } catch (_) {
      _proactiveTimer?.cancel();
      _proactiveTimer = Timer(const Duration(minutes: 15), () {
        unawaited(_runProactiveCareIfDue());
      });
    } finally {
      _proactiveRunInFlight = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _proactiveTimer?.cancel();
    super.dispose();
  }
}

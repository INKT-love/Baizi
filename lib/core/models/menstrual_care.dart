enum MenstrualPhase {
  unknown,
  period,
  postPeriod,
  ovulationWindow,
  prePeriod,
  expectedStart,
  delayed,
}

enum MenstrualCareDestination { recentConversation, dedicatedConversation }

class MenstrualCycleRecord {
  const MenstrualCycleRecord({
    required this.startDate,
    this.endDate,
    this.automatic = false,
  });
  final DateTime startDate;
  final DateTime? endDate;
  final bool automatic;

  Map<String, dynamic> toJson() => {
    'startDate': _day(startDate),
    'endDate': endDate == null ? null : _day(endDate!),
    'automatic': automatic,
  };
  factory MenstrualCycleRecord.fromJson(Map<String, dynamic> json) =>
      MenstrualCycleRecord(
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: json['endDate'] is String
            ? DateTime.parse(json['endDate'] as String)
            : null,
        automatic: json['automatic'] == true,
      );
}

class MenstrualCareProfile {
  const MenstrualCareProfile({
    required this.lastStartDate,
    this.cycleDays = 28,
    this.periodDays = 5,
    this.contextEnabled = true,
    this.remindersEnabled = false,
    this.autoRecordEnabled = true,
    this.reminderMinutes = 540,
    this.advanceReminderDays = 1,
    this.proactiveCareEnabled = false,
    this.proactiveCareMinutes = 540,
    this.proactiveCareDestination = MenstrualCareDestination.recentConversation,
    this.proactiveCareAllowMobileData = true,
    this.proactiveCareConversationId,
    this.proactiveCareLastAttemptDay,
    this.proactiveCareLastSuccessDay,
    this.proactiveCareLastError,
    this.records = const [],
    this.disabledConversationIds = const [],
  });
  final DateTime lastStartDate;
  final int cycleDays;
  final int periodDays;
  final bool contextEnabled;
  final bool remindersEnabled;
  final bool autoRecordEnabled;
  final int reminderMinutes;
  final int advanceReminderDays;
  final bool proactiveCareEnabled;
  final int proactiveCareMinutes;
  final MenstrualCareDestination proactiveCareDestination;
  final bool proactiveCareAllowMobileData;
  final String? proactiveCareConversationId;
  final String? proactiveCareLastAttemptDay;
  final String? proactiveCareLastSuccessDay;
  final String? proactiveCareLastError;
  final List<MenstrualCycleRecord> records;
  final List<String> disabledConversationIds;

  MenstrualCareProfile copyWith({
    DateTime? lastStartDate,
    int? cycleDays,
    int? periodDays,
    bool? contextEnabled,
    bool? remindersEnabled,
    bool? autoRecordEnabled,
    int? reminderMinutes,
    int? advanceReminderDays,
    bool? proactiveCareEnabled,
    int? proactiveCareMinutes,
    MenstrualCareDestination? proactiveCareDestination,
    bool? proactiveCareAllowMobileData,
    String? proactiveCareConversationId,
    bool clearProactiveCareConversationId = false,
    String? proactiveCareLastAttemptDay,
    String? proactiveCareLastSuccessDay,
    String? proactiveCareLastError,
    bool clearProactiveCareLastError = false,
    List<MenstrualCycleRecord>? records,
    List<String>? disabledConversationIds,
  }) => MenstrualCareProfile(
    lastStartDate: lastStartDate ?? this.lastStartDate,
    cycleDays: cycleDays ?? this.cycleDays,
    periodDays: periodDays ?? this.periodDays,
    contextEnabled: contextEnabled ?? this.contextEnabled,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    autoRecordEnabled: autoRecordEnabled ?? this.autoRecordEnabled,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    advanceReminderDays: advanceReminderDays ?? this.advanceReminderDays,
    proactiveCareEnabled: proactiveCareEnabled ?? this.proactiveCareEnabled,
    proactiveCareMinutes: proactiveCareMinutes ?? this.proactiveCareMinutes,
    proactiveCareDestination:
        proactiveCareDestination ?? this.proactiveCareDestination,
    proactiveCareAllowMobileData:
        proactiveCareAllowMobileData ?? this.proactiveCareAllowMobileData,
    proactiveCareConversationId: clearProactiveCareConversationId
        ? null
        : (proactiveCareConversationId ?? this.proactiveCareConversationId),
    proactiveCareLastAttemptDay:
        proactiveCareLastAttemptDay ?? this.proactiveCareLastAttemptDay,
    proactiveCareLastSuccessDay:
        proactiveCareLastSuccessDay ?? this.proactiveCareLastSuccessDay,
    proactiveCareLastError: clearProactiveCareLastError
        ? null
        : (proactiveCareLastError ?? this.proactiveCareLastError),
    records: records ?? this.records,
    disabledConversationIds:
        disabledConversationIds ?? this.disabledConversationIds,
  );
  Map<String, dynamic> toJson() => {
    'lastStartDate': _day(lastStartDate),
    'cycleDays': cycleDays,
    'periodDays': periodDays,
    'contextEnabled': contextEnabled,
    'remindersEnabled': remindersEnabled,
    'autoRecordEnabled': autoRecordEnabled,
    'reminderMinutes': reminderMinutes,
    'advanceReminderDays': advanceReminderDays,
    'proactiveCareEnabled': proactiveCareEnabled,
    'proactiveCareMinutes': proactiveCareMinutes,
    'proactiveCareDestination': proactiveCareDestination.name,
    'proactiveCareAllowMobileData': proactiveCareAllowMobileData,
    'proactiveCareConversationId': proactiveCareConversationId,
    'proactiveCareLastAttemptDay': proactiveCareLastAttemptDay,
    'proactiveCareLastSuccessDay': proactiveCareLastSuccessDay,
    'proactiveCareLastError': proactiveCareLastError,
    'records': records.map((e) => e.toJson()).toList(),
    'disabledConversationIds': disabledConversationIds,
  };
  factory MenstrualCareProfile.fromJson(
    Map<String, dynamic> json,
  ) => MenstrualCareProfile(
    lastStartDate: DateTime.parse(json['lastStartDate'] as String),
    cycleDays: (json['cycleDays'] as num?)?.toInt() ?? 28,
    periodDays: (json['periodDays'] as num?)?.toInt() ?? 5,
    contextEnabled: json['contextEnabled'] != false,
    remindersEnabled: json['remindersEnabled'] == true,
    autoRecordEnabled: json['autoRecordEnabled'] != false,
    reminderMinutes: (json['reminderMinutes'] as num?)?.toInt() ?? 540,
    advanceReminderDays: (json['advanceReminderDays'] as num?)?.toInt() ?? 1,
    proactiveCareEnabled: json['proactiveCareEnabled'] == true,
    proactiveCareMinutes:
        (json['proactiveCareMinutes'] as num?)?.toInt() ?? 540,
    proactiveCareDestination: MenstrualCareDestination.values.firstWhere(
      (value) => value.name == json['proactiveCareDestination'],
      orElse: () => MenstrualCareDestination.recentConversation,
    ),
    proactiveCareAllowMobileData: json['proactiveCareAllowMobileData'] != false,
    proactiveCareConversationId: json['proactiveCareConversationId'] as String?,
    proactiveCareLastAttemptDay: json['proactiveCareLastAttemptDay'] as String?,
    proactiveCareLastSuccessDay: json['proactiveCareLastSuccessDay'] as String?,
    proactiveCareLastError: json['proactiveCareLastError'] as String?,
    records: ((json['records'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MenstrualCycleRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    disabledConversationIds:
        ((json['disabledConversationIds'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
  );
}

class MenstrualStatus {
  const MenstrualStatus({
    required this.phase,
    required this.cycleDay,
    required this.expectedStartDate,
    required this.expectedEndDate,
    required this.irregular,
  });
  final MenstrualPhase phase;
  final int cycleDay;
  final DateTime expectedStartDate;
  final DateTime expectedEndDate;
  final bool irregular;
}

DateTime dayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
String _day(DateTime value) => dayOnly(value).toIso8601String();

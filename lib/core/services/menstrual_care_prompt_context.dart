import '../models/menstrual_care.dart';

class MenstrualCarePromptContext {
  static String? build(MenstrualCareProfile? profile, MenstrualStatus? status) {
    if (profile == null ||
        status == null ||
        status.phase == MenstrualPhase.unknown) {
      return null;
    }
    final label = switch (status.phase) {
      MenstrualPhase.period => '可能处于经期第 ${status.cycleDay} 天',
      MenstrualPhase.postPeriod => '可能处于经后阶段',
      MenstrualPhase.ovulationWindow => '可能处于排卵期附近（仅为日期估算）',
      MenstrualPhase.prePeriod => '可能临近经期',
      MenstrualPhase.expectedStart => '预计今天可能开始经期',
      MenstrualPhase.delayed => '经期可能延后',
      MenstrualPhase.unknown => '',
    };
    MenstrualCycleRecord? latestRecord;
    for (final record in profile.records) {
      if (dayOnly(record.startDate) == dayOnly(profile.lastStartDate)) {
        latestRecord = record;
      }
    }
    final latestEnd = latestRecord?.endDate;
    return '''<menstrual_care_context>
这是用户授权提供给你的本地经期关怀数据。最近一次经期开始日：${_formatDay(profile.lastStartDate)}。${latestEnd == null ? '最近一次经期尚未记录结束日。' : '最近一次经期结束日：${_formatDay(latestEnd)}。'} 平均周期：${profile.cycleDays} 天；经期持续：${profile.periodDays} 天；预计下次开始日：${_formatDay(status.expectedStartDate)}。当前状态：$label${status.irregular ? '；最近周期可能不规律。' : ''}
当用户询问其经期何时开始、何时结束、当前状态或下次预计时间时，必须直接依据上述数据回答，不要声称自己不知道、无法读取或没有记录。保持当前角色人设、系统提示与对话语气。只在用户正在讨论身体感受、休息、饮食、运动或确实相关的话题时，自然、简短地表达关心。不要主动打断无关对话，不作诊断、不提供避孕建议、不把冷饮或辛辣食物说成绝对禁忌。若用户提到严重疼痛、异常出血或持续明显不规律，建议咨询专业医生。
</menstrual_care_context>''';
  }

  static String _formatDay(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

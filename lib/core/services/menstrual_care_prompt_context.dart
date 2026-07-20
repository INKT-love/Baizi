import '../models/menstrual_care.dart';

class MenstrualCarePromptContext {
  static String? build(MenstrualStatus? status) {
    if (status == null || status.phase == MenstrualPhase.unknown) return null;
    final label = switch (status.phase) {
      MenstrualPhase.period => '可能处于经期第 ${status.cycleDay} 天',
      MenstrualPhase.postPeriod => '可能处于经后阶段',
      MenstrualPhase.ovulationWindow => '可能处于排卵期附近（仅为日期估算）',
      MenstrualPhase.prePeriod => '可能临近经期',
      MenstrualPhase.expectedStart => '预计今天可能开始经期',
      MenstrualPhase.delayed => '经期可能延后',
      MenstrualPhase.unknown => '',
    };
    return '''<menstrual_care_context>
用户的本地经期关怀状态：$label${status.irregular ? '；最近周期可能不规律。' : ''}
保持当前角色人设、系统提示与对话语气。只在用户正在讨论身体感受、休息、饮食、运动或确实相关的话题时，自然、简短地表达关心。不要主动打断无关对话，不作诊断、不提供避孕建议、不把冷饮或辛辣食物说成绝对禁忌。若用户提到严重疼痛、异常出血或持续明显不规律，建议咨询专业医生。
</menstrual_care_context>''';
  }
}

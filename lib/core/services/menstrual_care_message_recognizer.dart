enum MenstrualRecordIntent { none, start, end }

class MenstrualCareMessageRecognizer {
  static MenstrualRecordIntent recognize(String value) {
    final text = value.trim().replaceAll(RegExp(r'\s+'), '');
    if (text.length > 80 ||
        text.contains('“') ||
        text.contains('"') ||
        text.contains('角色扮演'))
      return MenstrualRecordIntent.none;
    if (RegExp(
      r'^(我|本人)(今天)?(来月经了?|来例假了?|大姨妈来了|姨妈来了|月经来了)[！!。.]?$',
    ).hasMatch(text))
      return MenstrualRecordIntent.start;
    if (RegExp(r'^(我|本人)(今天)?(月经结束了|例假结束了|大姨妈走了|姨妈走了)[！!。.]?$').hasMatch(text))
      return MenstrualRecordIntent.end;
    return MenstrualRecordIntent.none;
  }
}

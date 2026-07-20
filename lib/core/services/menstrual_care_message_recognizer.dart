enum MenstrualRecordIntent { none, start, end }

class MenstrualCareMessageRecognizer {
  static MenstrualRecordIntent recognize(String value) {
    final text = value.trim().replaceAll(RegExp(r'\s+'), '');
    if (text.length > 80 ||
        text.contains('“') ||
        text.contains('"') ||
        text.contains('角色扮演'))
      return MenstrualRecordIntent.none;
    final start = RegExp(r'(我|本人).{0,10}(月经|例假|大姨妈|姨妈|经期).{0,5}(来了|开始了?|第一天)');
    final startReverse = RegExp(r'(我|本人).{0,10}(开始来(月经|例假|大姨妈|姨妈)|来(月经|例假)了?)');
    if (start.hasMatch(text) || startReverse.hasMatch(text))
      return MenstrualRecordIntent.start;
    if (RegExp(
      r'(我|本人).{0,10}(月经|例假|大姨妈|姨妈|经期).{0,5}(结束了?|走了|干净了)',
    ).hasMatch(text))
      return MenstrualRecordIntent.end;
    return MenstrualRecordIntent.none;
  }
}

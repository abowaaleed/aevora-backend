/// استخراج تذكير من جملة المستخدم مثل:
/// «ذكرني بموعد الساعة العاشرة مساءً» أو «ذكرني بزيارة الساعة 8».
class ParsedChatReminder {
  final String title;
  final int hour;
  final int minute;

  const ParsedChatReminder({
    required this.title,
    required this.hour,
    required this.minute,
  });
}

const _hourWords = <String, int>{
  'الواحدة': 1,
  'واحدة': 1,
  'الثانية': 2,
  'ثانية': 2,
  'الثالثة': 3,
  'ثالثة': 3,
  'الرابعة': 4,
  'رابعة': 4,
  'الخامسة': 5,
  'خامسة': 5,
  'السادسة': 6,
  'سادسة': 6,
  'السابعة': 7,
  'سابعة': 7,
  'الثامنة': 8,
  'ثامنة': 8,
  'التاسعة': 9,
  'تاسعة': 9,
  'العاشرة': 10,
  'عاشرة': 10,
  'الحادية عشرة': 11,
  'الحادية عشر': 11,
  'الثانية عشرة': 12,
  'الثانية عشر': 12,
};

ParsedChatReminder? parseChatReminder(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final lower = text
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ّ', '');
  if (!RegExp(r'ذكرني|ذكريني').hasMatch(lower)) return null;

  var hour = 9;
  var minute = 0;
  final clock = RegExp(r'(?:الساعة|ساعه|ساعة)?\s*(\d{1,2})(?::(\d{2}))?').firstMatch(lower);
  if (clock != null) {
    hour = int.tryParse(clock.group(1) ?? '') ?? 9;
    minute = int.tryParse(clock.group(2) ?? '0') ?? 0;
  } else {
    for (final e in _hourWords.entries) {
      if (lower.contains(e.key)) {
        hour = e.value;
        break;
      }
    }
  }
  hour = hour.clamp(0, 23);
  minute = minute.clamp(0, 59);

  final evening = lower.contains('مساء') || lower.contains('ليلا') || lower.contains('الليل');
  final morning = lower.contains('صباح');
  if (evening && hour > 0 && hour < 12) hour += 12;
  if (morning && hour == 12) hour = 0;

  var title = text
      .replaceAll(RegExp(r'^(من فضلك|لو سمحت)?\s*'), '')
      .replaceAll(RegExp(r'ذكرني|ذكريني|ذكّرني'), '')
      .replaceAll(RegExp(r'^[\sبِب]+'), '')
      .trim();
  title = title.replaceAll(RegExp(r'\s*الساعة.+$'), '').trim();
  title = title.replaceAll(RegExp(r'\s*\d{1,2}(:\d{2})?\s*(صباحا?|مساءا?)?$'), '').trim();
  if (title.isEmpty) title = text.trim();

  return ParsedChatReminder(title: title, hour: hour, minute: minute);
}

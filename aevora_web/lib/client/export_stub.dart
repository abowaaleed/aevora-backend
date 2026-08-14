import 'package:flutter/services.dart';

/// تنفيذ «التصدير/المشاركة» على منصات الجوال (iOS/Android):
/// بناء النص والنسخ يعملان بالكامل، أما التنزيل كمكوّنات المتصفح (Web Share /
/// عنصر `<a>`) فغير متاح — يُستخدم بدلاً منه واجهة النسخ النظامية.
const String aevoraPromo = '''
━━━ جرّب «ايفورا» مجاناً ━━━
🤖 مساعد ذكي يجيب أسئلتك ويقرأ مستنداتك (PDF/TXT)
🧠 صديق شخصي يتذكرك ويصحح لغتك الإنجليزية يومياً
🔐 خصوصية كاملة: بياناتك على جهازك، بلا خوادم ولا تسجيل
💰 يعمل بمفاتيحك المجانية (Gemini / Groq) — بلا اشتراكات
📱 تطبيق ويب سريع (PWA) يعمل على الجوال والحاسوب

الرابط: https://abowaaleed.github.io/aevora-backend/
''';

/// بناء نص المحادثة الكامل (رسائل + ترويج) جاهز للإرسال في واتساب/تليجرام.
/// تُسبق الأسطر بشارة RLM لعرض النص من اليمين عند لصقه في Word.
String buildExportText(
  List<Map<String, dynamic>> messages, {
  String title = 'محادثة مع ايفورا',
  bool includePromo = true,
}) {
  final now = DateTime.now();
  final date =
      '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')} '
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

  final raw = StringBuffer()
    ..writeln(title)
    ..writeln('التاريخ: $date')
    ..writeln('━' * 38);

  final body =
      messages.where((m) => (m['text'] ?? '').toString().trim().isNotEmpty);
  var empty = true;
  for (final m in body) {
    empty = false;
    final who = m['role'] == 'user' ? 'أنت' : 'ايفورا';
    raw
      ..writeln('$who: ${m['text']}')
      ..writeln();
  }
  if (empty) {
    raw.writeln('(لا توجد رسائل بعد)');
  }

  if (includePromo) {
    raw
      ..writeln('━' * 38)
      ..writeln(aevoraPromo.trimRight());
  }

  final lines = raw.toString().split('\n');
  return lines.map((l) => '\u200F$l').join('\n');
}

/// مشاركة النص عبر نافذة المشاركة النظامية (واتساب/تليجرام/...).
/// على الجوال تُستخدم واجهة «نسخ ومشاركة» النظام عبر الحافظة.
Future<bool> tryShareText(String text, {String? title}) async {
  try {
    await copyTextToClipboard(text);
    return false;
  } catch (_) {
    return false;
  }
}

/// تنزيل النص كملف .txt على الجهاز.
/// على الجوال غير مدعوم في هذه النسخة — يُعرض التنبيه بدلاً من الصمت.
void downloadTextFile(String text, String filename) {
  throw UnsupportedError(
      'تنزيل الملفات غير متاح على الجوال حالياً — انسخ النص والصقه حيث شئت.');
}

Future<void> copyTextToClipboard(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
}

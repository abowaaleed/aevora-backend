import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// نص ترويجي يُرفق تلقائياً مع كل محادثة مصدَّرة لتعريف الآخرين بايفورا.
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

  final body = messages.where((m) => (m['text'] ?? '').toString().trim().isNotEmpty);
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

// ---------- مشاركة عبر Web Share API (إن دعمه المتصفح) ----------

@JS()
external NavigatorJS get navigator;

extension type NavigatorJS(JSObject _) implements JSObject {
  external JSPromise share(JSAny data);
}

/// مشاركة النص عبر نافذة المشاركة النظامية (واتساب/تليجرام/...) إن وُجدت.
/// تعيد false إذا كان المتصفح لا يدعم المشاركة.
Future<bool> tryShareText(String text, {String? title}) async {
  try {
    final data = JSObject()
      ..['title'] = (title ?? 'ايفورا').toJS
      ..['text'] = text.toJS;
    await navigator.share(data).toDart;
    return true;
  } catch (_) {
    return false;
  }
}

// ---------- تنزيل كنص ----------

/// تنزيل النص كملف .txt على الجهاز (بدون أي خادم).
void downloadTextFile(String text, String filename) {
  final uri = 'data:text/plain;charset=utf-8,${Uri.encodeComponent(text)}';
  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = uri;
  a.download = filename;
  web.document.body?.appendChild(a);
  a.click();
  a.remove();
}

// ---------- نسخ ----------

Future<void> copyTextToClipboard(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
}

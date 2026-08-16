import 'client_storage.dart';
import 'client_sync.dart';

/// عدّادات الاستهلاك اليومية المرتبطة بالمستخدم.
///
/// تُحفظ في IndexedDB كتاريخ يومي (`usage_history`) فلا تتصفّر عند تغيّر اليوم،
/// وتُرفع إلى Firestore مع الحساب لتبقى ملازمة للمستخدم في أي متصفح/هاتف.
class LocalUsage {
  static const _key = 'usage_history';

  /// الحدود الرسمية للطبقة المجانية (معلومة للعرض فقط) — لا تمثل عدّاداً
  /// محلياً دقيقاً: الحدود الفعلية يفرضها المزود لكل مشروع وقد تتغير.
  /// Gemini Flash: ~10 طلبات/دقيقة و1,500/يوم (تُعاد عند منتصف الليل PT).
  /// Groq Whisper: ~20 طلباً/دقيقة و2,000/يوم.
  /// Groq Llama (محادثة احتياطية): مجاني وسخي — أرقام عرض فقط.
  static const geminiLimit = 1500;
  static const geminiRpm = 10;
  static const whisperLimit = 2000;
  static const whisperRpm = 20;
  static const groqChatLimit = 5000;
  static const groqChatRpm = 30;

  static String _today() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  /// سجل كامل: { '2026-08-13': {gemini: n, whisper: n, companion: n} }.
  static Future<Map<String, dynamic>> history() async {
    final v = await LocalDb.kvGetValue(_key);
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  static Future<Map<String, dynamic>> _day(String date) async {
    final h = await history();
    final d = h[date];
    if (d is Map) return Map<String, dynamic>.from(d);
    return {'gemini': 0, 'whisper': 0, 'companion': 0, 'groq_chat': 0};
  }

  static Future<void> _writeDay(String date, Map<String, dynamic> day) async {
    final h = await history();
    h[date] = day;
    await LocalDb.kvPut(_key, h);
    SyncStore.schedulePush();
  }

  static Future<void> _bump(String field) async {
    final date = _today();
    final day = await _day(date);
    day[field] = ((day[field] as num?) ?? 0) + 1;
    await _writeDay(date, day);
  }

  static Future<void> recordGemini() => _bump('gemini');
  static Future<void> recordWhisper() => _bump('whisper');
  static Future<void> recordCompanion() => _bump('companion');
  static Future<void> recordGroqChat() => _bump('groq_chat');

  /// عدّاد استخدام النطق الاحترافي (صوت ايفورا عبر Gemini TTS):
  /// يُحسب كل طلب TTS + عدد الأحرف المُنطوقة حتى يتمكن المستخدم من
  /// متابعة حصة الصوت الاحترافي في يومه (عند استنفادها يتحول النطق
  /// تلقائياً إلى صوت المتصفح الأساسي).
  static Future<void> recordTts({int chars = 0}) async {
    final date = _today();
    final day = await _day(date);
    day['tts'] = ((day['tts'] as num?) ?? 0) + 1;
    day['tts_chars'] = ((day['tts_chars'] as num?) ?? 0) + chars;
    await _writeDay(date, day);
  }

  /// حالة اليوم الحالي بصيغة العرض (used/limit/remaining) مع معلومات
  /// الحدود الرسمية للعرض فقط (rpm) — ليطلع المستخدم على سبب أخطاء
  /// 429 التي قد تظهر رغم عدم بلوغ العدّاد اليومي.
  static Future<Map<String, dynamic>> today() async {
    final date = _today();
    final day = await _day(date);
    final gemini = (day['gemini'] as num?)?.toInt() ?? 0;
    final whisper = (day['whisper'] as num?)?.toInt() ?? 0;
    final groqChat = (day['groq_chat'] as num?)?.toInt() ?? 0;
    return {
      'date': date,
      'gemini': {
        'used': gemini,
        'limit': geminiLimit,
        'remaining': geminiLimit - gemini,
        'rpm': geminiRpm,
      },
      'stt_groq': {
        'used': whisper,
        'limit': whisperLimit,
        'remaining': whisperLimit - whisper,
        'rpm': whisperRpm,
      },
      'groq_chat': {
        'used': groqChat,
        'limit': groqChatLimit,
        'remaining': groqChatLimit - groqChat,
        'rpm': groqChatRpm,
      },
      'tts': {
        'requests': (day['tts'] as num?)?.toInt() ?? 0,
        'chars': (day['tts_chars'] as num?)?.toInt() ?? 0,
      },
      'companion': (day['companion'] as num?)?.toInt() ?? 0,
    };
  }

  /// دمج سجل قادم من السحابة مع المحلي (الأعلى لكل يوم/حقل يربح)
  /// حتى لا تُفقد العدادات عند استخدام أكثر من جهاز في نفس اليوم.
  static Future<void> mergeHistory(Map<String, dynamic> cloud) async {
    final local = await history();
    for (final e in cloud.entries) {
      final cd = e.value;
      if (cd is! Map) continue;
      final cm = Map<String, dynamic>.from(cd);
      final ld = local[e.key];
      if (ld is Map) {
        final merged = Map<String, dynamic>.from(ld);
        for (final fe in cm.entries) {
          final cv = fe.value is num ? (fe.value as num).toInt() : 0;
          final lv = (merged[fe.key] as num?)?.toInt() ?? 0;
          merged[fe.key] = cv > lv ? cv : lv;
        }
        local[e.key] = merged;
      } else {
        local[e.key] = cm;
      }
    }
    await LocalDb.kvPut(_key, local);
  }
}

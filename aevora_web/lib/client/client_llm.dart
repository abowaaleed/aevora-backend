import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'client_usage.dart';

/// رسالة محادثة بسيطة للطلبات المباشرة.
class ClientMsg {
  final String role; // 'user' | 'model'
  final String text;
  const ClientMsg(this.role, this.text);
}

const kDefaultModel = 'gemini-3.6-flash';

const _base = 'https://generativelanguage.googleapis.com/v1beta';

/// محرك الرد الحالي النشط — تُحدّثه المحادثة بعد كل رد ناجح ليعرف المستخدم
/// أي مزود يجيب الآن (جرّين = جيميناي، وقروك = Groq الاحتياطي).
enum ChatEngine { gemini, groq }

/// المؤشر الحي لمحرك الرد الحالي — تشترك به شاشة «الإعدادات» (العدّادات)
/// وشريط المحادثة لإظهار أي نموذج يعمل الآن (نقطة خضراء مشعّة).
final ValueNotifier<ChatEngine> activeChatEngine =
    ValueNotifier<ChatEngine>(ChatEngine.gemini);

/// استدعاء Gemini مباشرة من متصفح المستخدم بمفتاحه الخاص (بدون أي خادم وسيط).
Future<String> geminiStreamChat({
  required String apiKey,
  required List<ClientMsg> messages,
  String? system,
  double temperature = 0.7,
  String model = kDefaultModel,
  void Function(String partial)? onChunk,
  bool recordUsage = true,
}) async {
  if (apiKey.trim().isEmpty) {
    throw Exception('مفتاح Gemini غير مضبوط. أضِفه من الإعدادات.');
  }
  final url = Uri.parse(
      '$_base/models/$model:streamGenerateContent?alt=sse&key=${apiKey.trim()}');
  final req = http.Request('POST', url);
  req.headers['Content-Type'] = 'application/json';
  req.body = jsonEncode({
    'contents': [
      for (final m in messages)
        {
          'role': m.role == 'user' ? 'user' : 'model',
          'parts': [
            {'text': m.text},
          ],
        },
    ],
    if (system != null && system.trim().isNotEmpty)
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
    'generationConfig': {
      'temperature': temperature,
      'maxOutputTokens': 4096,
    },
  });

  final res = await req.send().timeout(const Duration(minutes: 4));
  // نُحصي كل طلب عالجه المزوّد فعلاً (أي رد لا يُرفض بالحصة 429) حتى تعكس
  // العدادات الاستهلاك الحقيقي — بما فيها التحليلات الخلفية والمحاولات
  // الفاشلة بأخطاء أخرى (400/500) التي تحسب على الحصة كذلك.
  if (res.statusCode != 429 && recordUsage) LocalUsage.recordGemini();
  if (res.statusCode != 200) {
    final body = await res.stream.bytesToString();
    throw Exception(extractGeminiError(body, res.statusCode));
  }

  var full = '';
  await for (final line
      in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
    final t = line.trim();
    if (!t.startsWith('data:')) continue;
    final dataStr = t.substring(5).trim();
    if (dataStr.isEmpty || dataStr == '[DONE]') continue;
    try {
      final obj = jsonDecode(dataStr);
      final parts = (obj['candidates'] as List?)?[0]?['content']?['parts'] as List?;
      if (parts != null) {
        for (final p in parts) {
          final txt = (p as Map?)?['text']?.toString() ?? '';
          if (txt.isNotEmpty) {
            full += txt;
            onChunk?.call(txt);
          }
        }
      }
    } catch (_) {}
  }
  if (full.trim().isEmpty) {
    throw Exception('لم يصل رد من Gemini. تحقق من المفتاح أو حاول لاحقاً.');
  }
  return full;
}

/// نسخة غير متدفقة (للتحليل الخلفي مثل استخراج الذاكرة).
Future<String> geminiChatSync({
  required String apiKey,
  required List<ClientMsg> messages,
  String? system,
  double temperature = 0.3,
  String model = kDefaultModel,
  bool recordUsage = true,
}) async {
  if (apiKey.trim().isEmpty) {
    throw Exception('مفتاح Gemini غير مضبوط.');
  }
  final url = Uri.parse('$_base/models/$model:generateContent?key=${apiKey.trim()}');
  final req = http.Request('POST', url);
  req.headers['Content-Type'] = 'application/json';
  req.body = jsonEncode({
    'contents': [
      for (final m in messages)
        {
          'role': m.role == 'user' ? 'user' : 'model',
          'parts': [
            {'text': m.text},
          ],
        },
    ],
    if (system != null && system.trim().isNotEmpty)
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
    'generationConfig': {
      'temperature': temperature,
      'maxOutputTokens': 2048,
    },
  });

  final res = await http.post(url, headers: {'Content-Type': 'application/json'}, body: req.body)
      .timeout(const Duration(minutes: 3));
  if (res.statusCode != 429 && recordUsage) LocalUsage.recordGemini();
  if (res.statusCode != 200) {
    throw Exception(extractGeminiError(utf8.decode(res.bodyBytes), res.statusCode));
  }
  final obj = jsonDecode(utf8.decode(res.bodyBytes));
  final parts = (obj['candidates'] as List?)?[0]?['content']?['parts'] as List?;
  final text = parts == null
      ? ''
      : parts.map((p) => (p as Map?)?['text']?.toString() ?? '').join();
  if (text.trim().isEmpty) {
    throw Exception('لم يصل رد من Gemini.');
  }
  return text;
}

/// محادثة عبر Groq (نماذج Llama السريعة والمجانية) — بديل احتياطي تلقائي
/// عند تعذّر Gemini (نفاد حصة/ازدحام)، فيبقى التطبيق يعمل دون أي انقطاع.
Future<String> groqChatStream({
  required String apiKey,
  required List<ClientMsg> messages,
  String? system,
  double temperature = 0.7,
  String model = 'llama-3.3-70b-versatile',
  void Function(String partial)? onChunk,
}) async {
  if (apiKey.trim().isEmpty) {
    throw Exception('مفتاح Groq غير مضبوط.');
  }
  final req = http.Request(
      'POST', Uri.parse('https://api.groq.com/openai/v1/chat/completions'));
  req.headers['Content-Type'] = 'application/json';
  req.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
  req.body = jsonEncode({
    'model': model,
    'messages': [
      if (system != null && system.trim().isNotEmpty)
        {'role': 'system', 'content': system},
      for (final m in messages)
        {
          'role': m.role == 'user' ? 'user' : 'assistant',
          'content': m.text,
        },
    ],
    'temperature': temperature,
    'stream': true,
  });

  final res = await req.send().timeout(const Duration(minutes: 4));
  if (res.statusCode != 200) {
    final body = await res.stream.bytesToString();
    throw Exception(_groqError(body, res.statusCode));
  }

  var full = '';
  await for (final line
      in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
    final t = line.trim();
    if (!t.startsWith('data:')) continue;
    final dataStr = t.substring(5).trim();
    if (dataStr.isEmpty || dataStr == '[DONE]') continue;
    try {
      final obj = jsonDecode(dataStr);
      final delta = (obj['choices'] as List?)?[0]?['delta'] as Map?;
      final txt = delta?['content']?.toString() ?? '';
      if (txt.isNotEmpty) {
        full += txt;
        onChunk?.call(txt);
      }
    } catch (_) {}
  }
  if (full.trim().isEmpty) {
    throw Exception('لم يصل رد من Groq. حاول لاحقاً.');
  }
  LocalUsage.recordGroqChat();
  return full;
}

/// ترجمة أخطاء Groq إلى رسائل عربية قابلة للفهم.
String _groqError(String body, int status) {
  var raw = '';
  try {
    final obj = jsonDecode(body);
    raw = obj['error']?['message']?.toString() ?? '';
  } catch (_) {}
  final r = raw.toLowerCase();
  if (status == 429) {
    if (r.contains('per_minute') || r.contains('per minute') || r.contains('too many requests')) {
      return 'رسائل Groq كثيرة في الدقيقة — انتظر قليلاً وأعد المحاولة.';
    }
    if (r.contains('daily') || r.contains('per_day') || r.contains('per day') || r.contains('quota')) {
      return 'استُنفدت حصة Groq اليوم — تعود تلقائياً عند منتصف الليل.';
    }
    return 'Groq مزدحمة حالياً — أعد المحاولة بعد قليل.';
  }
  if (status == 401 && (r.contains('key') || r.contains('invalid') || r.contains('unauthorized'))) {
    return 'مفتاح Groq غير صالح — حدّثه من الإعدادات.';
  }
  if (raw.isNotEmpty) return raw;
  return 'فشل الاتصال بـ Groq ($status)';
}

/// ترجمة أخطاء Gemini (429 وغيرها) إلى رسائل عربية صحيحة السبب.
/// الترتيب مهم: أخطاء «في الدقيقة» (RPM) تُفحص أولاً لأن رسالة Google فيها
/// كلمة «quota» أحياناً، فلو تأخر فحصها لأُبلغ المستخدم خطأً أنه استنفد
/// حصته اليومية رغم أن حصته اليومية سليمة.
String extractGeminiError(String body, int status) {
  var raw = '';
  try {
    final obj = jsonDecode(body);
    raw = obj['error']?['message']?.toString() ?? '';
  } catch (_) {}
  final r = raw.toLowerCase();

  if (status == 429) {
    // ازدحام مؤقت للنموذج (يُرسل Google «high demand»/«overloaded»): يزول
    // من تلقاء نفسه خلال دقائق — ليس نفاداً للحصة اليومية.
    if (r.contains('high demand') ||
        r.contains('overloaded') ||
        r.contains('unavailable') ||
        r.contains('temporarily')) {
      return 'خدمة Gemini مزدحمة حالياً (ازدحام مؤقت). انتظر قليلاً وأعد '
          'المحاولة — ليس هذا نفاداً لحصتك اليومية.';
    }
    // حد الطلبات في الدقيقة (RPM) — رسالة Google تشمل «per minute» أو
    // «per_minute» مهما كانت صيغتها، ويجب تمييزها عن الحصة اليومية.
    if (r.contains('per_minute') ||
        r.contains('per minute') ||
        r.contains('requests per minute') ||
        r.contains('too many requests') ||
        r.contains('rate limit') ||
        r.contains('rpm')) {
      return 'تجاوزت حد الطلبات في الدقيقة (حوالي ${LocalUsage.geminiRpm} '
          'طلبات/دقيقة). انتظر دقيقة وأعد المحاولة.';
    }
    // الحصة اليومية (RPD).
    if (r.contains('per_day') ||
        r.contains('per day') ||
        r.contains('requests per day') ||
        r.contains('daily') ||
        r.contains('resource has been exhausted')) {
      return 'استُنفدت حصة محادثات Gemini اليوم (1,500 طلب). تُعاد الحصة '
          'تلقائياً عند منتصف الليل بتوقيت المحيط الهادئ.';
    }
    // أي 429 آخر عام.
    return 'وصلت حداً من حدود Gemini (429). انتظر قليلاً وأعد المحاولة.';
  }
  if ((status == 400 || status == 403) &&
      (r.contains('api key') || r.contains('invalid') || r.contains('unauthorized'))) {
    return 'مفتاح Gemini غير صالح أو محذوف. حدّثه من الإعدادات.';
  }
  if (raw.isNotEmpty) return raw;
  return 'فشل الاتصال بـ Gemini ($status)';
}

/// تحويل أي خطأ قادم من المحادثة إلى رسالة ودّية مهذّبة تُعرض للمستخدم بدل
/// النص التقني الخام («خطأ: Exception: ...»). تُعيد صياغة المشكلة بأسلوب
/// لطيف غير مخيف مع الحفاظ على جوهر المعلومة (مثلاً: الحصة اليومية تتجدد
/// عند منتصف الليل).
String friendlyError(Object error) {
  final msg = error.toString().replaceFirst('Exception: ', '').trim();
  final low = msg.toLowerCase();

  // الحصة اليومية: أخطر المزعجة — تُصاغ ببساطة وألفة كأنه «نهاية رحلة اليوم».
  if (low.contains('استُنفدت حصة') ||
      low.contains('resource has been exhausted') ||
      (low.contains('quota') && low.contains('day'))) {
    return 'وصلنا معاً إلى آخر حديث اليوم، وكان وقتاً جميلاً. لا تقلق — '
        'الحصة تتجدد تلقائياً بعد منتصف الليل بإذن الله، ونكمل من حيث توقفنا.';
  }
  if (low.contains('تجاوزت حد الطلبات في الدقيقة') ||
      low.contains('requests per minute') ||
      low.contains('rpm')) {
    return 'واو، رسائل متلاحقة! هدّئ السرعة قليلاً وأعد المحاولة خلال دقيقة.';
  }
  if (low.contains('مزدحمة') ||
      low.contains('high demand') ||
      low.contains('429')) {
    return 'خدمة الذكاء الاصطناعي مشغولة قليلاً هذه اللحظة. انتظر لحظات '
        'وأعد المحاولة — سنكمل حديثنا فوراً.';
  }
  if (low.contains('مفتاح') &&
      (low.contains('غير صالح') ||
          low.contains('محذوف') ||
          low.contains('غير مضبوط'))) {
    return 'يبدو أن مفتاح Gemini يحتاج إلى تحديث بسيط — أضِفه أو حدّثه من '
        'الإعدادات وسنكمل حديثنا فوراً.';
  }
  if (low.contains('لم يصل رد')) {
    return 'لم يصل الرد هذه المرة، أعد المحاولة خلال لحظات.';
  }
  if (msg.isEmpty || low.contains('exception')) {
    return 'حدث أمر غير متوقع... أعد المحاولة خلال لحظات.';
  }
  return 'آسف، تعثّر الرد هذه المرة. أعد المحاولة خلال لحظات.';
}

import 'dart:convert';

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
  if (res.statusCode != 200) {
    final body = await res.stream.bytesToString();
    throw Exception(_extractError(body, res.statusCode));
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
  if (recordUsage) LocalUsage.recordGemini();
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
  if (res.statusCode != 200) {
    throw Exception(_extractError(utf8.decode(res.bodyBytes), res.statusCode));
  }
  final obj = jsonDecode(utf8.decode(res.bodyBytes));
  final parts = (obj['candidates'] as List?)?[0]?['content']?['parts'] as List?;
  final text = parts == null
      ? ''
      : parts.map((p) => (p as Map?)?['text']?.toString() ?? '').join();
  if (text.trim().isEmpty) {
    throw Exception('لم يصل رد من Gemini.');
  }
  if (recordUsage) LocalUsage.recordGemini();
  return text;
}

String _extractError(String body, int status) {
  var raw = '';
  try {
    final obj = jsonDecode(body);
    raw = obj['error']?['message']?.toString() ?? '';
  } catch (_) {}
  final r = raw.toLowerCase();

  // رسالة Google عن الازدحام المؤقت للنموذج: خطأ 429 لكنه غير متعلق
  // بالحصة اليومية — يزول من تلقاء نفسه خلال دقائق.
  if (status == 429 && r.contains('high demand')) {
    return 'خدمة Gemini مزدحمة حالياً (ازدحام مؤقت). انتظر دقيقة وأعد المحاولة — '
        'ليس هذا نفاداً لحصتك اليومية.';
  }
  if (status == 429 &&
      (r.contains('rate limit') ||
          r.contains('too many requests') ||
          r.contains('requests per minute') ||
          r.contains('rpm'))) {
    return 'تجاوزت حد الطلبات في الدقيقة (حوالي ${LocalUsage.geminiRpm} طلبات/دقيقة). '
        'انتظر دقيقة وأعد المحاولة.';
  }
  if (status == 429 &&
      (r.contains('requests per day') ||
          r.contains('daily') ||
          r.contains('quota') ||
          r.contains('resource has been exhausted'))) {
    return 'استُنفدت حصة محادثات Gemini اليوم (1,500 طلب). تُعاد الحصة تلقائياً '
        'عند منتصف الليل بتوقيت المحيط الهادئ.';
  }
  if (status == 429) {
    return 'وصلت حداً من حدود Gemini (429). انتظر دقيقة وأعد المحاولة.';
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'client_plan.dart';
import 'client_usage.dart';
import 'voice_platform_stub.dart'
    if (dart.library.js_interop) 'voice_platform_web.dart' as voice_platform;

// ---------- النطق الاحترافي عبر Gemini TTS (نفس مفتاح Gemini، بدون خادم) ----------

/// نموذج TTS الصوتي الاحترافي من Google (أصوات طبيعية، يدعم العربية).
const String kGeminiTtsModel = 'gemini-3.1-flash-tts-preview';
const String kGeminiTtsVoice = 'Kore';

/// توليد صوت احترافي للنص عبر Gemini TTS ويعيده بصيغة WAV (جاهز للتشغيل).
/// تُحوَّل البيانات الخام (audio/L16) إلى حاوية WAV ليعمل على المتصفح
/// وعلى أجهزة الجوال.
Future<Uint8List> geminiTextToSpeech({
  required String apiKey,
  required String text,
  String voice = kGeminiTtsVoice,
}) async {
  if (apiKey.trim().isEmpty) {
    throw Exception('أضِف مفتاح Gemini من الإعدادات للنطق الاحترافي.');
  }
  var clean = text.trim();
  if (clean.isEmpty) throw Exception('لا يوجد نص للنطق');
  clean = clean
      .replaceAll(RegExp(r'[*_`#>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (clean.length > 3000) clean = '${clean.substring(0, 3000)}.';
  final prompt = 'Synthesize speech for the following text. '
      'Speak naturally. Do not read this instruction aloud.\n\n$clean';

  final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$kGeminiTtsModel:generateContent?key=${apiKey.trim()}');
  final res = await http
      .post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            'responseModalities': ['AUDIO'],
            'speechConfig': {
              'voiceConfig': {
                'prebuiltVoiceConfig': {'voiceName': voice},
              },
            },
          },
        }),
      )
      .timeout(const Duration(minutes: 3));

  if (res.statusCode != 200) {
    throw Exception('النطق الاحترافي فشل (${res.statusCode}): '
        '${sttErrorMessage(utf8.decode(res.bodyBytes), res.statusCode)}');
  }
  final obj = jsonDecode(utf8.decode(res.bodyBytes));
  final parts =
      (obj['candidates'] as List?)?[0]?['content']?['parts'] as List?;
  final inline = parts == null || parts.isEmpty
      ? null
      : (parts.first as Map?)?['inlineData'] as Map?;
  final data = inline?['data']?.toString() ?? '';
  if (data.isEmpty) throw Exception('لم يصل صوت من Gemini.');
  final mime = inline?['mimeType']?.toString() ?? 'audio/L16;rate=24000';
  return _toPlayableWav(base64Decode(data), mime);
}

/// تحويل البيانات إلى WAV إن كانت خام (L16) وإبقائها كما هي إن كانت قابلة للتشغيل.
Uint8List _toPlayableWav(Uint8List raw, String mime) {
  final m = mime.toLowerCase();
  if (m.startsWith('audio/wav') ||
      m.startsWith('audio/mpeg') ||
      m.startsWith('audio/mp3') ||
      m.startsWith('audio/ogg') ||
      m.startsWith('audio/opus') ||
      m.startsWith('audio/mp4') ||
      m.startsWith('audio/aac')) {
    return raw;
  }
  var rate = 24000;
  for (final part in m.split(';')) {
    final t = part.trim().toLowerCase();
    if (t.startsWith('rate=')) {
      final v = int.tryParse(t.substring(5).trim());
      if (v != null && v > 0) rate = v;
    }
  }
  return _wrapPcmInWav(raw, rate);
}

/// بناء رأس WAV (PCM 16-bit أحادي القناة) وإلحاق البيانات الخام.
Uint8List _wrapPcmInWav(Uint8List pcm, int sampleRate) {
  final dataSize = pcm.length;
  final bytes = ByteData(44 + dataSize);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);
  final out = Uint8List.fromList(bytes.buffer.asUint8List());
  out.setAll(44, pcm);
  return out;
}

// ---------- التعرف على الصوت عبر Groq Whisper (مباشرة من الجهاز) ----------

/// تفريغ تسجيل WAV إلى نص عبر Groq Whisper بمفتاح المستخدم مباشرة
/// (يعمل على المتصفح وعلى الجوال).
Future<String> groqTranscribe({
  required String apiKey,
  required List<int> wavBytes,
}) async {
  if (apiKey.trim().isEmpty) {
    throw Exception('أضِف مفتاح Groq من الإعدادات لتفعيل التعرف على الصوت.');
  }
  final req = http.MultipartRequest(
    'POST',
    Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions'),
  );
  req.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
  req.files.add(http.MultipartFile.fromBytes(
    'file',
    wavBytes,
    filename: 'voice_query.wav',
  ));
  req.fields['model'] = 'whisper-large-v3';
  req.fields['response_format'] = 'json';

  final res = await req.send().timeout(const Duration(minutes: 2));
  final body = await res.stream.bytesToString();
  if (res.statusCode != 200) {
    throw Exception('التعرف على الصوت فشل (${res.statusCode}): '
        '${sttErrorMessage(body, res.statusCode)}');
  }
  final text = (jsonDecode(body)['text'] ?? '').toString().trim();
  if (text.isEmpty) {
    throw Exception('لم يُفهم الكلام. حاول مرة أخرى.');
  }
  LocalUsage.recordWhisper();
  return text;
}

/// ترجمة خطأ مزود الخدمة (Gemini TTS أو Groq Whisper) إلى رسالة عربية
/// قابلة للفهم — خاصة أخطاء 429 الشائعة التي تُربك المستخدم.
String sttErrorMessage(String body, int status) {
  var raw = '';
  try {
    final obj = jsonDecode(body);
    raw = obj['error']?['message']?.toString() ?? '';
  } catch (_) {}
  final r = raw.toLowerCase();
  if (status == 429) {
    if (r.contains('high demand')) {
      return 'الخدمة مزدحمة حالياً (ازدحام مؤقت) — أعد المحاولة بعد قليل.';
    }
    if (r.contains('daily') ||
        r.contains('quota') ||
        r.contains('resource has been exhausted')) {
      return 'استُنفدت حصة هذا النوع اليوم — تعود تلقائياً عند منتصف الليل.';
    }
    return 'تجاوزت حد الطلبات في الدقيقة — انتظر دقيقة وأعد المحاولة.';
  }
  if (status == 401 && (r.contains('api key') || r.contains('invalid'))) {
    return 'مفتاح غير صالح — حدّثه من الإعدادات.';
  }
  if (raw.isNotEmpty) return raw;
  return body;
}

// ---------- نطق النص الذكي (احترافي ← صوت المتصفح) ----------

bool _hasArabic(String text) => RegExp(r'[\u0600-\u06FF]').hasMatch(text);

String detectLang(String text) => _hasArabic(text) ? 'ar-SA' : 'en-US';

/// يُستدعى عند أي تفاعل مستخدم (إرسال/تسجيل) لتهيئة الصوت داخل إيماءة
/// المستخدم حتى لا يُحجب التشغيل بسياسة التشغيل التلقائي (المتصفح).
void warmUpAudio() => voice_platform.warmUpAudio();

/// نطق النص: يفضّل النطق الاحترافي المتدفق من Gemini (يبدأ فوراً) إن وُجد
/// المفتاح، وإلا يعود فوراً لصوت المتصفح (Web Speech). خطة «مميز/مُدارة»
/// ترفع الحد اليومي للنطق الاحترافي إلى اللانهاية.
Future<void> speakSmart(
  String text, {
  String? apiKey,
  double rate = 1.0,
  void Function()? onStart,
}) async {
  final hasKey = apiKey != null && apiKey.trim().isNotEmpty;
  final premium = PlanStore.current.value.isPremium;

  if (hasKey && premium) {
    // خطة مدفوعة: نطق احترافي بلا حدود.
    try {
      LocalUsage.recordTts(chars: text.trim().length);
      await voice_platform
          .speakProfessionalStreaming(text, apiKey: apiKey, rate: rate, onStart: onStart);
      return;
    } catch (e) {
      voice_platform.stopPlaybackNow();
      PlaybackController.instance.fallbackNotice.value =
          _friendlyTtsFallbackReason(e.toString());
    }
  } else if (hasKey) {
    // الخطة المجانية: حد يومي للنطق الاحترافي.
    final used = (await LocalUsage.today())['tts'];
    final usedChars = (used is Map ? used['chars'] : null) as num? ?? 0;
    if (usedChars >= PlanStore.freeProfessionalTtsCharsPerDay) {
      PlaybackController.instance.fallbackNotice.value =
          'وصلت إلى الحد المجاني اليومي للنطق الاحترافي '
          '(${PlanStore.freeProfessionalTtsCharsPerDay} حرف). '
          'رقِّ خطتك من «الإعدادات ← الاشتراك والترقية» للاستفادة بلا حدود.';
    } else {
      try {
        LocalUsage.recordTts(chars: text.trim().length);
        await voice_platform.speakProfessionalStreaming(text,
            apiKey: apiKey, rate: rate, onStart: onStart);
        return;
      } catch (e) {
        voice_platform.stopPlaybackNow();
        PlaybackController.instance.fallbackNotice.value =
            _friendlyTtsFallbackReason(e.toString());
      }
    }
  }

  if (voice_platform.isBrowserSpeechSupported) {
    await voice_platform.speakText(text, rate: rate, onStart: onStart);
    return;
  }
  final m = !hasKey
      ? 'النطق الصوتي يتطلب مفتاح Gemini (النطق الاحترافي) — أضِفه من الإعدادات، أو رقِّ خطتك لميزة «مُدارة».'
      : 'النطق الاحترافي غير متاح حالياً، وصوت المتصفح لا يعمل على الجوال. أضِف مفتاح Gemini وحاول مجدداً.';
  PlaybackController.instance.fallbackNotice.value = m;
  throw Exception(m);
}

/// ترجمة سبب فشل النطق الاحترافي إلى رسالة واضحة للمستخدم — يميّز
/// الازدحام المؤقت (يُعاد قريباً) عن نفاد الحصة اليومية (يعود غداً).
String _friendlyTtsFallbackReason(String raw) {
  final r = raw.toLowerCase();
  if (r.contains('high demand')) {
    return 'خدمة النطق الاحترافي مزدحمة حالياً — يُستخدم صوت المتصفح مؤقتاً، '
        'وأعد المحاولة بعد قليل.';
  }
  if (r.contains('429') &&
      (r.contains('rate limit') || r.contains('too many requests'))) {
    return 'تجاوزت حد النطق الاحترافي في الدقيقة — يُستخدم صوت المتصفح مؤقتاً، '
        'وانتظر دقيقة قبل إعادة المحاولة.';
  }
  if (r.contains('429') ||
      r.contains('quota') ||
      r.contains('resource has been exhausted') ||
      r.contains('rate limit')) {
    return 'استُنفدت حصة النطق الاحترافي اليوم، يُستخدم الآن صوت المتصفح الأساسي. '
        'سيعود الصوت الطبيعي غداً.';
  }
  if (r.contains('التشغيل التلقائي')) {
    return 'منع المتصفح النطق الاحترافي (سياسة التشغيل التلقائي)، يُستخدم صوت المتصفح الأساسي.';
  }
  return 'النطق الاحترافي غير متاح حالياً، يُستخدم صوت المتصفح الأساسي.';
}

// ---------- التحكم العالمي بصوت ايفورا (شريط التحكم بالصوت) ----------

enum PlaybackStatus { idle, loading, speaking, paused }

/// واجهة واحدة للتشغيل تتحكم بها جميع الشاشات، وتُشغّل شريط التحكم بالصوت:
/// تشغيل · إيقاف مؤقت · استئناف · إيقاف كامل.
class PlaybackController {
  PlaybackController._();
  static final PlaybackController instance = PlaybackController._();

  /// حالة التشغيل الحالية (مصدر ظهور شريط التحكم).
  final ValueNotifier<PlaybackStatus> status =
      ValueNotifier<PlaybackStatus>(PlaybackStatus.idle);

  /// النص الجاري نطقه (يُعرض مختصراً في الشريط).
  final ValueNotifier<String> currentText = ValueNotifier<String>('');

  /// هوية الرسالة الناطقة حالياً (لتظليل زر الاستماع في الفقاعة).
  final ValueNotifier<String?> activeId = ValueNotifier<String?>(null);

  /// سبب التحول المؤقت إلى صوت المتصفح الأساسي (إن حدث) — يُعرض في شريط
  /// الصوت حتى لا يتفاجأ المستخدم بانخفاض جودة الصوت.
  final ValueNotifier<String?> fallbackNotice = ValueNotifier<String?>(null);

  int _token = 0;

  bool get isActive => status.value != PlaybackStatus.idle;

  /// تشغيل النص صوتياً. إن كان نفس النص (نفس [messageId]) قيد التشغيل
  /// يُوقَف التشغيل كاملاً — لتلائم سلوك زر الفقاعة (تشغيل/إيقاف).
  Future<void> play(
    String text, {
    String? apiKey,
    double rate = 1.0,
    String? messageId,
  }) async {
    if (text.trim().isEmpty) return;
    if (messageId != null &&
        activeId.value == messageId &&
        status.value == PlaybackStatus.speaking) {
      stop();
      return;
    }
    stop();
    currentText.value = text;
    activeId.value = messageId;
    fallbackNotice.value = null;
    status.value = PlaybackStatus.loading;
    final token = ++_token;
    try {
      await speakSmart(text, apiKey: apiKey, rate: rate, onStart: () {
        if (token == _token) status.value = PlaybackStatus.speaking;
      });
    } catch (_) {}
    if (token == _token) {
      status.value = PlaybackStatus.idle;
      activeId.value = null;
    }
  }

  /// إيقاف مؤقت دقيق: يُعلَّق الصوت في موضعه الحالي فيستأنف من نفس النقطة
  /// تماماً عند الطلب — صوت المتصفح عبر Web Speech، والنطق المتدفق عبر
  /// تعليق سياق الصوت.
  Future<void> pause() async {
    if (status.value != PlaybackStatus.speaking) return;
    if (!voice_platform.activeEngineIsBrowser &&
        !voice_platform.activeEngineIsStream) {
      return;
    }
    try {
      await voice_platform.pauseActiveEngine();
    } catch (_) {
      return;
    }
    status.value = PlaybackStatus.paused;
  }

  /// استئناف الصوت من موضع الإيقاف المؤقت بالضبط.
  Future<void> resume() async {
    if (status.value != PlaybackStatus.paused) return;
    try {
      await voice_platform.resumeActiveEngine();
    } catch (_) {
      stop();
      return;
    }
    status.value = PlaybackStatus.speaking;
  }

  /// إيقاف كامل: يقطع الصوت ويعيد الشريط إلى الحالة الخاملة.
  void stop() {
    _token++;
    voice_platform.stopPlaybackNow();
    status.value = PlaybackStatus.idle;
    activeId.value = null;
    currentText.value = '';
    fallbackNotice.value = null;
  }
}

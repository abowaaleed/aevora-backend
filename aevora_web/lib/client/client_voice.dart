import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'client_plan.dart';
import 'client_usage.dart';
import 'client_backup_voice.dart';
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

// ---------- صوت إيدج الاحترافي المجاني (بديل فوري بلا مفتاح) ----------
//
// خدمة نطق مايكروسوفت إيدج الطبيعية: تُستخدم مجاناً بدون أي مفتاح عبر
// نفس البروتوكول الذي يستعمله متصفح إيدج، وتوفر أصواتاً احترافية للعربية
// (ar-SA-HamedNeural / ar-SA-ZariyahNeural) والإنجليزية. جميع الدوال هنا
// خالصة (بدون إدخال/إخراج) لسهولة اختبارها؛ النقل الفعلي (WebSocket) وتشغيل
// الصوت في ملفا المنصة.

/// المفتاح العام الموثوق لخدمة صوت إيدج (ثابت من متصفح إيدج، بلا مفاتيح خاصة).
const String kEdgeTtsTrustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';

/// الصوت العربي الاحترافي (سعودي — ذكر).
const String kEdgeArabicVoice = 'ar-SA-HamedNeural';

/// الصوت العربي الاحترافي (سعودي — أنثى).
const String kEdgeArabicFemaleVoice = 'ar-SA-ZariyahNeural';

/// الصوت الإنجليزي الاحترافي.
const String kEdgeEnglishVoice = 'en-US-JennyNeural';

/// إصدار Chromium الذي تُطابِق عليه إيدج توقيع الحماية (Sec-MS-GEC).
const String kEdgeSecMsGecVersion = '1-143.0.3650.75';

/// صيغة الصوت المطلوبة من إيدج (MP3 48kbps).
const String kEdgeAudioFormat = 'audio-24khz-48kbitrate-mono-mp3';

/// اختيار صوت إيدج المناسب للغة النص (العربية ← صوت سعودي طبيعي).
String edgeVoiceForLang(String lang) {
  final l = lang.toLowerCase();
  if (l.startsWith('ar')) return kEdgeArabicVoice;
  return kEdgeEnglishVoice;
}

/// استخراج نص XML-safe من النص المطلوب نطقه: يزيل أحرف التحكم غير المدعومة
/// (التي ترفضها الخدمة أحياناً في ملفات OCR) ثم يفلتر رموز الترميز.
String _edgeCleanText(String text) {
  final chars = text.split('');
  final out = StringBuffer();
  for (final c in chars) {
    final code = c.codeUnitAt(0);
    if (code <= 8 || (code >= 11 && code <= 12) || (code >= 14 && code <= 31)) {
      out.write(' ');
    } else {
      out.write(c);
    }
  }
  return out.toString();
}

/// ترميز XML لنص داخل عنصر `speak` حتى لا يكسر الوسوم.
String edgeXmlEscape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// تقسيم النص النظيف إلى مقاطع لا تتجاوز [maxChars] حرفاً عند حدود الكلمات
/// (تجنّباً لحد رسالة الخدمة — إيدج يقبل نحو 4096 بايت لكل طلب).
List<String> edgeTextChunks(String text, {int maxChars = 3000}) {
  final clean = _edgeCleanText(text).trim();
  if (clean.isEmpty) return const [];
  if (clean.length <= maxChars) return [clean];
  final parts = clean
      .split(RegExp(r'[.!?؟،:؛\n]+\s*'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final chunks = <String>[];
  var buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) {
      chunks.add(buf.toString().trim());
      buf = StringBuffer();
    }
  }

  for (final p in parts) {
    if (p.length > maxChars) {
      flush();
      var rest = p;
      while (rest.length > maxChars) {
        chunks.add(rest.substring(0, maxChars));
        rest = rest.substring(maxChars);
      }
      if (rest.isNotEmpty) buf.write(rest);
    } else if (buf.length + p.length + 1 > maxChars) {
      flush();
      buf.write(p);
    } else {
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(p);
    }
  }
  flush();
  return chunks.isEmpty ? [clean] : chunks;
}

/// توقيع زمني بأسلوب إيدج (رأس X-Timestamp) — بصيغة JavaScript Date.
String edgeTimestamp(DateTime now) {
  const wd = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  const mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${wd[now.weekday - 1]} ${mo[now.month - 1]} ${two(now.day)} '
      '${now.year} ${two(now.hour)}:${two(now.minute)}:${two(now.second)} '
      'GMT+0000 (Coordinated Universal Time)';
}

/// توليد توقيع الحماية Sec-MS-GEC الذي تطلبه خدمة إيدج منذ 2024:
/// SHA-256(وقت ويندوز المقرب لخمس دقائق + المفتاح الموثوق) بالأحرف الكبيرة.
String edgeSecMsGec(DateTime now, {String token = kEdgeTtsTrustedClientToken}) {
  final unix = now.toUtc().millisecondsSinceEpoch / 1000.0;
  const winEpoch = 11644473600;
  final secs = unix + winEpoch;
  final rounded = (secs - (secs % 300)).round();
  final ticks = (rounded * 10000000).toStringAsFixed(0);
  return sha256.convert(ascii.encode('$ticks$token')).toString().toUpperCase();
}

/// معرف اتصال عشوائي (32 رقماً سداسياً) — تطلبه الخدمة كمعرّف للجلسة.
String edgeConnectionId([math.Random? rng]) {
  final r = rng ?? math.Random.secure();
  final sb = StringBuffer();
  for (var i = 0; i < 32; i++) {
    sb.write('0123456789abcdef'[r.nextInt(16)]);
  }
  return sb.toString();
}

/// رابط WebSocket الكامل لخدمة إيدج (يُربط من ملف المنصة).
String edgeTtsWsUrl({String connectionId = '', DateTime? now}) {
  final id = connectionId.isEmpty ? edgeConnectionId() : connectionId;
  final gec = edgeSecMsGec(now ?? DateTime.now());
  return 'wss://speech.platform.bing.com/consumer/speech/synthesize/'
      'readaloud/edge/v1?TrustedClientToken=$kEdgeTtsTrustedClientToken'
      '&ConnectionId=$id&Sec-MS-GEC=$gec'
      '&Sec-MS-GEC-Version=$kEdgeSecMsGecVersion';
}

/// رسالة إعداد الاتصال (تُرسل نصياً فور فتح WebSocket).
String edgeConfigMessage({DateTime? now}) {
  final ts = edgeTimestamp(now ?? DateTime.now());
  return 'X-Timestamp:$ts\r\n'
      'Content-Type:application/json; charset=utf-8\r\n'
      'Path:speech.config\r\n\r\n'
      '{"context":{"synthesis":{"audio":{"metadataoptions":'
      '{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
      '"outputFormat":"$kEdgeAudioFormat"}}}}\r\n';
}

/// رسالة SSML لكل مقطع نصي (تُرسل نصياً؛ إيدج يعيد الصوت بعدها).
String edgeSsmlMessage({
  required String voice,
  required String text,
  double rate = 1.0,
  DateTime? now,
}) {
  final ts = edgeTimestamp(now ?? DateTime.now());
  final ratePct = '${((rate - 1) * 100).round()}%';
  final body = "<speak version='1.0' "
      "xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
      "<voice name='$voice'>"
      "<prosody pitch='+0Hz' rate='$ratePct' volume='+0%'>"
      '${edgeXmlEscape(_edgeCleanText(text))}'
      '</prosody></voice></speak>';
  return 'X-RequestId:${edgeConnectionId()}\r\n'
      'Content-Type:application/ssml+xml\r\n'
      'X-Timestamp:${ts}Z\r\n'
      'Path:ssml\r\n\r\n'
      '$body';
}

/// استخراج حمولة الصوت من إطار WebSocket ثنائي لخدمة إيدج:
/// أول بايتين = طول الترويسة (كبير نهاية)، ثم الترويسة، ثم \r\n، ثم الصوت.
Uint8List edgeAudioFromFrame(Uint8List frame) {
  if (frame.length < 2) return Uint8List(0);
  final headerLen = (frame[0] << 8) | frame[1];
  if (headerLen + 2 > frame.length) return Uint8List(0);
  return frame.sublist(headerLen + 2);
}

/// هل الرسالة النصية من إيدج تعلن نهاية المقطع (turn.end)؟
bool edgeIsTurnEnd(String message) => message.contains('Path: turn.end');

/// يُستدعى عند أي تفاعل مستخدم (إرسال/تسجيل) لتهيئة الصوت داخل إيماءة
/// المستخدم حتى لا يُحجب التشغيل بسياسة التشغيل التلقائي (المتصفح).
void warmUpAudio() => voice_platform.warmUpAudio();

/// نطق النص بصوت Gemini البشري أولاً، ثم تحويل صامت إلى صوت إيدج ثم
/// صوت الجهاز ثم صوت المتصفح عند نفاد الحصة أو أي تعذّر — بلا انقطاع محسوس.
Future<void> speakSmart(
  String text, {
  String? apiKey,
  double rate = 1.0,
  void Function()? onStart,
}) async {
  final hasKey = apiKey != null && apiKey.trim().isNotEmpty;

  if (hasKey) {
    if (await _tryProfessional(text, apiKey, rate, onStart)) return;
  }

  try {
    await voice_platform.speakEdgeTts(text, rate: rate, onStart: onStart);
    return;
  } catch (_) {
    voice_platform.stopPlaybackNow();
  }

  if (BackupVoice.instance.isReady) {
    if (await BackupVoice.instance.speak(text, rate: rate, onStart: onStart)) {
      return;
    }
  }

  if (voice_platform.isBrowserSpeechSupported) {
    await voice_platform.speakText(text,
        rate: rate == 1.0 ? 0.95 : rate, onStart: onStart);
    return;
  }
  throw Exception(
      'لا يتوفر أي محرك نطق حالياً — أضف مفتاح Gemini أو جرّب على متصفح حديث.');
}

/// محاولة النطق الاحترافي عبر Gemini؛ ترجع true إن نجح التشغيل.
/// يُسجَّل الاستهلاك بعد النجاح فقط (المحاولات المرفوضة لا تُحسب).
Future<bool> _tryProfessional(
  String text,
  String apiKey,
  double rate,
  void Function()? onStart,
) async {
  try {
    await voice_platform.speakProfessionalStreaming(text,
        apiKey: apiKey, rate: rate, onStart: onStart);
    LocalUsage.recordTts(chars: text.trim().length);
    return true;
  } catch (_) {
    voice_platform.stopPlaybackNow();
    return false;
  }
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

  /// عدد أحرف النطق الاحترافي المنطوقة اليوم (بمفتاح المستخدم) —
  /// مصدر شريط الصوت وعدّاد الإعدادات، ويتجدد بعد كل نطق.
  final ValueNotifier<int> todayTtsChars = ValueNotifier<int>(0);

  /// حد اليوم المجاني للنطق الاحترافي (بلا حدود لمشتركي «مميز/مُدارة»).
  final ValueNotifier<int> ttsCharsLimit =
      ValueNotifier<int>(PlanStore.freeProfessionalTtsCharsPerDay);

  int _token = 0;

  bool get isActive => status.value != PlaybackStatus.idle;

  /// تحديث عدّاد أحرف النطق الاحترافي من السجل المحلي (يُستدعى بعد النطق
  /// وعند ظهور شريط الصوت).
  Future<void> refreshTtsCounter() async {
    try {
      final t = await LocalUsage.today();
      final tts = t['tts'];
      todayTtsChars.value = ((tts is Map ? tts['chars'] : null) as num?)?.toInt() ?? 0;
    } catch (_) {}
  }

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
    unawaited(refreshTtsCounter());
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

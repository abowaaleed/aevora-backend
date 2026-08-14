import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'client_usage.dart';

// ---------- النطق الاحترافي عبر Gemini TTS (نفس مفتاح Gemini، بدون خادم) ----------

/// نموذج TTS الصوتي الاحترافي من Google (أصوات طبيعية، يدعم العربية).
const kGeminiTtsModel = 'gemini-3.1-flash-tts-preview';
const kGeminiTtsVoice = 'Kore';

/// توليد صوت احترافي للنص عبر Gemini TTS ويعيده بصيغة WAV (جاهز للتشغيل).
/// تُحوَّل البيانات الخام (audio/L16) إلى حاوية WAV ليتمكن المتصفح من تشغيلها.
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
    throw Exception(
        'النطق الاحترافي فشل (${res.statusCode}): ${_sttError(utf8.decode(res.bodyBytes))}');
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

web.HTMLAudioElement? _professionalPlayer;
String? _currentUrl;

/// تشغيل صوت احترافي مولّد من Gemini عبر عنصر صوت في المتصفح
/// (يُنتظر توليد الصوت كاملاً أولاً ثم يُشغّل — النسخة غير المتدفقة).
Future<void> speakProfessional(
  String text, {
  required String apiKey,
  double rate = 1.0,
  void Function()? onStart,
}) async {
  final wav = await geminiTextToSpeech(apiKey: apiKey, text: text);
  final audio = _professionalPlayer ??= web.HTMLAudioElement();
  _stopProfessionalPlayer();

  final parts = [wav.toJS].toJS as JSArray<JSAny>;
  final blob = web.Blob(
    parts,
    web.BlobPropertyBag(type: 'audio/wav'),
  );
  final url = web.URL.createObjectURL(blob);
  _currentUrl = url;
  audio.src = url;
  audio.playbackRate = rate;

  final completer = Completer<void>();
  audio.addEventListener('ended', ((web.Event _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS);
  audio.addEventListener('error', ((web.Event _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS);

  await audio.play().toDart;
  onStart?.call();
  await completer.future
      .timeout(const Duration(seconds: 120), onTimeout: () {});
  _revokeAudioUrl();
}

void _stopProfessionalPlayer() {
  final audio = _professionalPlayer;
  if (audio != null) {
    audio.pause();
    audio.currentTime = 0;
    audio.src = '';
  }
  _revokeAudioUrl();
}

void _revokeAudioUrl() {
  final url = _currentUrl;
  if (url != null && url.isNotEmpty) {
    web.URL.revokeObjectURL(url);
    _currentUrl = null;
  }
}

// ---------- النطق الاحترافي المتدفق (يبدأ فوراً بدل انتظار الملف كاملاً) ----------

web.AudioContext? _audioCtx;
final List<web.AudioBufferSourceNode> _streamSources = [];
bool _streamStop = false;
Completer<void>? _streamCompleter;
web.AudioBufferSourceNode? _streamLast;

/// عدّادات لتقدير موضع الإيقاف المؤقت في النطق المتدفق (أُطر/عيّنات في الثانية).
int _streamPlayedFrames = 0;
int _streamSampleRate = 24000;

web.AudioContext _ensureAudioContext() {
  var ctx = _audioCtx;
  if (ctx == null) {
    ctx = web.AudioContext();
    _audioCtx = ctx;
  }
  return ctx;
}

/// يُستدعى عند أي تفاعل مستخدم (إرسال/تسجيل) لإنشاء سياق الصوت داخل إيماءة
/// المستخدم حتى لا يُحجب التشغيل المتدفق لاحقاً بسياسة التشغيل التلقائي.
void warmUpAudio() {
  try {
    final ctx = _ensureAudioContext();
    if (ctx.state == 'suspended') {
      unawaited(ctx.resume().toDart);
    }
  } catch (_) {}
}

void _stopStreamPlayback() {
  _streamStop = true;
  for (final s in _streamSources) {
    try {
      s.stop();
    } catch (_) {}
  }
  _streamSources.clear();
  _streamLast = null;
  final c = _streamCompleter;
  if (c != null && !c.isCompleted) c.complete();
  _streamCompleter = null;
}

/// نطق احترافي متدفق: يبدأ إصدار الصوت فور وصول أول مقطع من Gemini
/// (بدل انتظار التوليد الكامل)، مع تشغيل تدريجي عبر Web Audio API.
Future<void> speakProfessionalStreaming(
  String text, {
  required String apiKey,
  double rate = 1.0,
  void Function()? onStart,
}) async {
  _stopStreamPlayback();
  _streamStop = false;
  _streamPlayedFrames = 0;
  _streamSampleRate = 24000;
  final ctx = _ensureAudioContext();
  var started = false;
  try {
    if (ctx.state == 'suspended') {
      await ctx.resume().toDart;
    }
  } catch (_) {}
  // إن أصر المتصفح على إبقاء الصوت معلقاً فلن يسمع المستخدم شيئاً؛
  // ارجع خطأً ليُحوَّل النطق إلى صوت المتصفح الفوري.
  if (ctx.state == 'suspended') {
    throw Exception('سياسة التشغيل التلقائي أوقفت الصوت الاحترافي');
  }

  final completer = Completer<void>();
  _streamCompleter = completer;
  // الوقت المطلق (في خط زمني سياق الصوت) الذي يبدأ عنده المقطع التالي.
  // يُضبَط دائماً ألا يكون في الماضي: فالمقطع الأول قد يصل بعد زمن شبكة
  // أطول من 0.08 ثانية، فإذا بُرمج في الماضي بدأت المقاطع الأولى دفعة واحدة
  // فينتج صوت مشوَّش في أول الكلام.
  var nextStart = 0.0;

  await _streamTtsChunks(
    apiKey: apiKey,
    text: text,
    onChunk: (pcm, sampleRate) {
      if (_streamStop) return;
      final frames = pcm.length ~/ 2;
      if (frames <= 0) return;
      _streamSampleRate = sampleRate;
      _streamPlayedFrames += frames;
      final f32 = Float32List(frames);
      final bd = ByteData.sublistView(pcm);
      for (var i = 0; i < frames; i++) {
        f32[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
      }
      final buffer = ctx.createBuffer(1, frames, sampleRate);
      buffer.copyToChannel(f32.toJS, 0);
      final src = ctx.createBufferSource();
      src.buffer = buffer;
      src.playbackRate.value = rate;
      src.connect(ctx.destination);
      // لا تُبرمج المقاطع في الماضي أبداً حتى لا تتزاحم وتشوّش أول الكلام.
      if (nextStart < ctx.currentTime + 0.05) {
        nextStart = ctx.currentTime + 0.05;
      }
      src.start(nextStart);
      if (!started) {
        started = true;
        onStart?.call();
      }
      // مدة التشغيل الفعلية مع مراعاة سرعة التشغيل لتفادي فجوات/تداخل.
      nextStart += frames / sampleRate / rate;
      _streamLast = src;
      _streamSources.add(src);
      src.onended = ((web.Event _) {
        if (!_streamStop &&
            identical(src, _streamLast) &&
            !completer.isCompleted) {
          completer.complete();
        }
      }).toJS;
    },
  );

  if (nextStart > 0 && !_streamStop) {
    await completer.future.timeout(
      Duration(seconds: 1 + (nextStart - ctx.currentTime + 10).ceil()),
      onTimeout: () {},
    );
  } else if (!completer.isCompleted) {
    completer.complete();
  }
  _streamSources.clear();
  _streamLast = null;
}

/// سحب صوت Gemini على شكل أجزاء (SSE) واستدعاء [onChunk] لكل مقطع L16 يصل.
Future<void> _streamTtsChunks({
  required String apiKey,
  required String text,
  required void Function(Uint8List pcm, int sampleRate) onChunk,
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
      'https://generativelanguage.googleapis.com/v1beta/models/$kGeminiTtsModel:streamGenerateContent?alt=sse&key=${apiKey.trim()}');
  final req = http.Request('POST', url)
    ..headers['Content-Type'] = 'application/json'
    ..body = jsonEncode({
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
            'prebuiltVoiceConfig': {'voiceName': kGeminiTtsVoice},
          },
        },
      },
    });

  final res = await req.send().timeout(const Duration(seconds: 60));
  if (res.statusCode != 200) {
    throw Exception('النطق الاحترافي فشل (${res.statusCode}): '
        '${_sttError(await res.stream.bytesToString())}');
  }

  var pending = '';
  await for (final frag in res.stream.transform(utf8.decoder)) {
    if (_streamStop) break;
    pending += frag;
    while (true) {
      final cr = pending.indexOf('\r\n\r\n');
      final lf = pending.indexOf('\n\n');
      int end;
      int width;
      if (cr != -1 && (lf == -1 || cr < lf)) {
        end = cr;
        width = 4;
      } else if (lf != -1) {
        end = lf;
        width = 2;
      } else {
        break;
      }
      final block = pending.substring(0, end);
      pending = pending.substring(end + width);
      _handleSseBlock(block, onChunk);
    }
  }
  _handleSseBlock(pending, onChunk);
}

void _handleSseBlock(
    String block, void Function(Uint8List pcm, int sampleRate) onChunk) {
  for (final line in block.split('\n')) {
    final t = line.trim();
    if (!t.startsWith('data:')) continue;
    final data = t.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') continue;
    try {
      final root = jsonDecode(data);
      if (root is! Map) continue;
      final parts = (root['candidates'] as List?)?[0]?['content']?['parts'];
      if (parts is! List) continue;
      for (final p in parts) {
        final inline = (p as Map?)?['inlineData'];
        if (inline is! Map) continue;
        final b64 = (inline['data'] ?? '').toString();
        if (b64.isEmpty) continue;
        onChunk(base64Decode(b64),
            _sampleRateFromMime((inline['mimeType'] ?? '').toString()));
      }
    } catch (_) {}
  }
}

int _sampleRateFromMime(String mime) {
  var rate = 24000;
  for (final part in mime.split(';')) {
    final t = part.trim().toLowerCase();
    if (t.startsWith('rate=')) {
      final v = int.tryParse(t.substring(5).trim());
      if (v != null && v > 0) rate = v;
    }
  }
  return rate;
}

/// نطق النص: يفضّل النطق الاحترافي المتدفق من Gemini (يبدأ فوراً) إن وُجد
/// المفتاح، وإلا يعود فوراً لصوت المتصفح (Web Speech).
Future<void> speakSmart(
  String text, {
  String? apiKey,
  double rate = 1.0,
  void Function()? onStart,
}) async {
  if (apiKey != null && apiKey.trim().isNotEmpty) {
    try {
      await speakProfessionalStreaming(text,
          apiKey: apiKey, rate: rate, onStart: onStart);
      return;
    } catch (_) {
      _stopStreamPlayback();
    }
  }
  await speakText(text, rate: rate, onStart: onStart);
}

// ---------- واجهات Web Speech API (احتياطي مجاني بدون مفتاح) ----------

@JS()
external SpeechSynthesis? get speechSynthesis;

extension type SpeechSynthesis(JSObject _) implements JSObject {
  external void speak(SpeechSynthesisUtterance utterance);
  external void cancel();
  external void pause();
  external void resume();
  external JSArray<SpeechSynthesisVoice> getVoices();
}

extension type SpeechSynthesisUtterance._(JSObject _) implements JSObject {
  external factory SpeechSynthesisUtterance(String text);
  external String get lang;
  external set lang(String v);
  external SpeechSynthesisVoice get voice;
  external set voice(SpeechSynthesisVoice v);
  external double get rate;
  external set rate(double v);
  external double get pitch;
  external set pitch(double v);
  external JSFunction? get onend;
  external set onend(JSFunction? v);
  external JSFunction? get onerror;
  external set onerror(JSFunction? v);
}

extension type SpeechSynthesisVoice(JSObject _) implements JSObject {
  external String get lang;
  external String get name;
}

extension type SpeechSynthesisEvent(JSObject _) implements JSObject {
  external int get charIndex;
}

bool _hasArabic(String text) => RegExp(r'[\u0600-\u06FF]').hasMatch(text);

String detectLang(String text) => _hasArabic(text) ? 'ar-SA' : 'en-US';

bool get isSpeechSynthesisSupported => speechSynthesis != null;

/// نطق النص صوتياً عبر المتصفح (مجاني، متعدد اللغات، بدون خادم).
Future<void> speakText(
  String text, {
  double rate = 1.0,
  void Function()? onStart,
}) async {
  final synth = speechSynthesis;
  if (synth == null) {
    throw Exception('نطق الصوت غير مدعوم في هذا المتصفح');
  }
  synth.cancel();

  final lang = detectLang(text);
  final utterance = SpeechSynthesisUtterance(text);
  utterance.lang = lang;
  utterance.rate = rate;
  utterance.pitch = 1.0;

  // اختيار صوت طبيعي مطابق للغة إن توفر.
  try {
    final voices = synth.getVoices().toDart;
    if (voices.isNotEmpty) {
      final match = voices.firstWhere(
        (v) => v.lang.toLowerCase() == lang.toLowerCase(),
        orElse: () => voices.firstWhere(
          (v) => v.lang.toLowerCase().startsWith(lang.split('-').first),
          orElse: () => voices.first,
        ),
      );
      utterance.voice = match;
    }
  } catch (_) {}

  final completer = Completer<void>();
  utterance.onend = ((SpeechSynthesisEvent _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  utterance.onerror = ((SpeechSynthesisEvent _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;

  synth.speak(utterance);
  onStart?.call();
  await completer.future.timeout(const Duration(seconds: 60), onTimeout: () {});
}

void stopSpeaking() {
  speechSynthesis?.cancel();
  _stopProfessionalPlayer();
  _stopStreamPlayback();
}

// ---------- التعرف على الصوت عبر Groq Whisper (مباشرة من المتصفح) ----------

/// تفريغ تسجيل WAV إلى نص عبر Groq Whisper بمفتاح المستخدم مباشرة.
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
    throw Exception('التعرف على الصوت فشل (${res.statusCode}): ${_sttError(body)}');
  }
  final text = (jsonDecode(body)['text'] ?? '').toString().trim();
  if (text.isEmpty) {
    throw Exception('لم يُفهم الكلام. حاول مرة أخرى.');
  }
  LocalUsage.recordWhisper();
  return text;
}

String _sttError(String body) {
  try {
    final obj = jsonDecode(body);
    return obj['error']?['message']?.toString() ?? body;
  } catch (_) {
    return body;
  }
}

// ---------- التحكم العالمي بصوت ايفورا (شريط التحكم بالصوت) ----------

enum PlaybackStatus { idle, loading, speaking, paused }

/// متوسط تقريبي لعدد الأحرف المنطوقة في الثانية (لتقدير موضع الاستئناف).
const double _kCharsPerSecond = 16;

/// تقدير عدد الأحرف التي قُطعت فعلياً من النص عند لحظة الإيقاف المؤقت،
/// وذلك من مدة الصوت المتدفق الذي صُدِّر حتى الآن.
int _estimateResumeIndex(String text) {
  if (_streamSampleRate <= 0 || text.isEmpty) return 0;
  final elapsedSec = _streamPlayedFrames / _streamSampleRate;
  final chars = (elapsedSec * _kCharsPerSecond).round();
  return chars.clamp(0, text.length);
}

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

  String? _apiKey;
  double _rate = 1.0;
  int _resumeIndex = 0;
  bool _browserSpeech = false;
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
    _apiKey = apiKey;
    _rate = rate;
    _resumeIndex = 0;
    _browserSpeech = apiKey == null || apiKey.trim().isEmpty;
    currentText.value = text;
    activeId.value = messageId;
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

  /// إيقاف مؤقت:
  /// - صوت المتصفح (Web Speech) يدعم الاستئناف من نفس الموضع مباشرة.
  /// - النطق الاحترافي المتدفق يُوقَف ويُقدَّر موضع التوقف ليعاد توليد ما تبقّى.
  Future<void> pause() async {
    if (status.value != PlaybackStatus.speaking) return;
    if (_browserSpeech) {
      speechSynthesis?.pause();
    } else {
      _resumeIndex = _estimateResumeIndex(currentText.value);
      // نُبطل مستقبل التشغيل القديم حتى لا يعيد الحالة إلى (خامل) بعد توقفه.
      _token++;
      speechSynthesis?.pause();
      _stopProfessionalPlayer();
      _stopStreamPlayback();
    }
    status.value = PlaybackStatus.paused;
  }

  /// استئناف الصوت من موضع الإيقاف المؤقت.
  Future<void> resume() async {
    if (status.value != PlaybackStatus.paused) return;
    if (!_browserSpeech) {
      final text = currentText.value;
      if (text.isEmpty) {
        stop();
        return;
      }
      final remaining = text.substring(_resumeIndex.clamp(0, text.length)).trim();
      if (remaining.isEmpty) {
        stop();
        return;
      }
      status.value = PlaybackStatus.loading;
      final token = ++_token;
      try {
        await speakSmart(remaining, apiKey: _apiKey, rate: _rate, onStart: () {
          if (token == _token) status.value = PlaybackStatus.speaking;
        });
      } catch (_) {}
      if (token == _token) {
        status.value = PlaybackStatus.idle;
        activeId.value = null;
      }
      return;
    }
    final synth = speechSynthesis;
    if (synth == null) {
      stop();
      return;
    }
    synth.resume();
    status.value = PlaybackStatus.speaking;
  }

  /// إيقاف كامل: يقطع الصوت ويعيد الشريط إلى الحالة الخاملة.
  void stop() {
    _token++;
    stopSpeaking();
    status.value = PlaybackStatus.idle;
    activeId.value = null;
    currentText.value = '';
    _resumeIndex = 0;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'client_voice.dart';

/// مكوّن تشغيل الصوت على المتصفح (Web Audio API + Web Speech API):
/// النطق الاحترافي المتدفق من Gemini، وصوت المتصفح الأساسي المجاني.
///
/// على منصات الجوال يُستخدم `voice_platform_stub.dart` بدلاً منه
/// (تشغيل WAV عبر audioplayers بدون صوت المتصفح).

enum SpeechEngine { none, browser, stream }

SpeechEngine _activeEngine = SpeechEngine.none;

bool get activeEngineIsBrowser => _activeEngine == SpeechEngine.browser;
bool get activeEngineIsStream => _activeEngine == SpeechEngine.stream;

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

bool get isBrowserSpeechSupported => speechSynthesis != null;

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
  _activeEngine = SpeechEngine.browser;
  synth.cancel();

  final lang = detectLang(text);
  final utterance = SpeechSynthesisUtterance(text);
  utterance.lang = lang;
  utterance.rate = rate;
  utterance.pitch = 1.0;

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
  _activeEngine = SpeechEngine.none;
}

// ---------- النطق الاحترافي المتدفق (Web Audio API) ----------

web.AudioContext? _audioCtx;
final List<web.AudioBufferSourceNode> _streamSources = [];
bool _streamStop = false;
Completer<void>? _streamCompleter;
web.AudioBufferSourceNode? _streamLast;

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
  _activeEngine = SpeechEngine.stream;
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
  var nextStart = 0.0;

  await _streamTtsChunks(
    apiKey: apiKey,
    text: text,
    onChunk: (pcm, sampleRate) {
      if (_streamStop) return;
      final frames = pcm.length ~/ 2;
      if (frames <= 0) return;
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
    await _waitForStreamEnd(ctx, nextStart, completer);
  } else if (!completer.isCompleted) {
    completer.complete();
  }
  _streamSources.clear();
  _streamLast = null;
  _activeEngine = SpeechEngine.none;
}

/// انتظار انتهاء النطق المتدفق. أثناء الإيقاف المؤقت يُعلَّق سياق الصوت
/// فلا يتقدم [ctx.currentTime] وتبقى الحلقة منتظرة حتى الاستئناف أو الإيقاف.
Future<void> _waitForStreamEnd(
  web.AudioContext ctx,
  double endTime,
  Completer<void> completer,
) async {
  while (true) {
    if (_streamStop || completer.isCompleted) return;
    if (ctx.currentTime >= endTime - 0.02) return;
    await Future.delayed(const Duration(milliseconds: 150));
  }
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
        '${sttErrorMessage(await res.stream.bytesToString(), res.statusCode)}');
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

/// إيقاف أي صوت نشط فوراً (صوت المتصفح والنطق المتدفق).
void stopPlaybackNow() {
  try {
    speechSynthesis?.cancel();
  } catch (_) {}
  _stopStreamPlayback();
  _activeEngine = SpeechEngine.none;
}

/// إيقاف مؤقت: يُعلَّق الصوت في موضعه الحالي فيستأنف من نفس النقطة عند الطلب.
Future<void> pauseActiveEngine() async {
  if (_activeEngine == SpeechEngine.browser) {
    speechSynthesis?.pause();
  } else if (_activeEngine == SpeechEngine.stream) {
    try {
      await _ensureAudioContext().suspend().toDart;
    } catch (_) {
      throw Exception('pause-failed');
    }
  }
}

/// استئناف الصوت من موضع الإيقاف المؤقت بالضبط.
Future<void> resumeActiveEngine() async {
  if (_activeEngine == SpeechEngine.browser) {
    final synth = speechSynthesis;
    if (synth == null) throw Exception('resume-failed');
    synth.resume();
  } else if (_activeEngine == SpeechEngine.stream) {
    try {
      await _ensureAudioContext().resume().toDart;
    } catch (_) {
      throw Exception('resume-failed');
    }
  }
}

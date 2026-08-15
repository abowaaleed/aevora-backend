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
  external bool get speaking;
  external JSFunction? get onvoiceschanged;
  external set onvoiceschanged(JSFunction? v);
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
  external double get volume;
  external set volume(double v);
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

/// هل المتصفح من فئة iOS (سفاري/كروم/فايرفوكس على iPhone/iPad)؟
/// iOS يحتاج تفعيل محرك النطق داخل إيماءة مستخدم، وإلا كان الصوت صامتاً.
bool get _isIos {
  try {
    final ua = web.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') ||
        ua.contains('ipad') ||
        ua.contains('ipod');
  } catch (_) {
    return false;
  }
}

/// ذاكرة مؤقتة لأصوات المتصفح: في iOS/Safari قائمة [getVoices] تصل فارغة
/// ثم تُملأ بعد حدث `voiceschanged` — نحفظها لنستعملها في اختيار الصوت.
List<SpeechSynthesisVoice> _voiceCache = const [];
bool _speechInited = false;

void _initBrowserSpeech() {
  if (_speechInited) return;
  _speechInited = true;
  final synth = speechSynthesis;
  if (synth == null) return;
  synth.onvoiceschanged = ((JSObject _) {
    try {
      _voiceCache = synth.getVoices().toDart;
    } catch (_) {}
  }).toJS;
  try {
    _voiceCache = synth.getVoices().toDart;
  } catch (_) {}
}

/// انتظار تحميل قائمة الأصوات (iOS/Safari تُملأ بعد `voiceschanged`)
/// مع مهلة قصيرة ثم المتابعة بأي قائمة متاحة.
Future<void> _ensureVoices(SpeechSynthesis synth) async {
  if (_voiceCache.isNotEmpty) return;
  try {
    _voiceCache = synth.getVoices().toDart;
  } catch (_) {}
  if (_voiceCache.isNotEmpty) return;
  final completer = Completer<void>();
  final previous = synth.onvoiceschanged;
  synth.onvoiceschanged = ((JSObject _) {
    if (!completer.isCompleted) {
      try {
        _voiceCache = synth.getVoices().toDart;
      } catch (_) {}
      completer.complete();
    }
  }).toJS;
  try {
    await completer.future.timeout(const Duration(milliseconds: 1500));
  } catch (_) {}
  synth.onvoiceschanged = previous;
}

/// اختيار أفضل صوت متاح للغة المطلوبة من بين أصوات المتصفح، بترتيب الجودة:
/// يفضّل دائماً الصوت الطبيعي (Natural) ثم المحسّن (Enhanced) ثم العصري
/// «Online» (يولّده المتصفح مباشرة بجودة أعلى)، ثم أصوات Google على أندرويد،
/// ثم «Maged» — أفضل صوت عربي على iOS. وإن لم يوجد صوت للغة يُرك المتصفح
/// يبحث بنفسه (دون تعيين voice).
SpeechSynthesisVoice? _pickBestVoice(String lang) {
  final voices = _voiceCache;
  if (voices.isEmpty) return null;
  final exact = lang.toLowerCase();
  final base = lang.split('-').first.toLowerCase();
  SpeechSynthesisVoice? best;
  var bestScore = -1;
  for (final v in voices) {
    final l = v.lang.toLowerCase();
    if (l != exact && l != base && !l.startsWith('$base-')) continue;
    final score = _voiceQualityScore(v);
    if (score > bestScore) {
      bestScore = score;
      best = v;
    }
  }
  return best;
}

/// تقييم جودة صوت المتصفح: «Natural» أعلى جودة (عصبية)، ثم «Enhanced»، ثم
/// «Online» (توليد مباشر)، ثم أصوات «Google» على أندرويد، ثم «Maged» —
/// الصوت العربي الأفضل على iOS. الأسماء تُستخدم مع قائمة أصوات المتصفح
/// نفسها (اللغة معروفة من [SpeechSynthesisVoice.lang]).
int _voiceQualityScore(SpeechSynthesisVoice v) {
  final name = v.name.toLowerCase();
  final lang = v.lang.toLowerCase();
  var score = 0;
  if (lang.startsWith('ar')) score += 10;
  if (name.contains('natural')) score += 100;
  if (name.contains('enhanced')) score += 90;
  if (name.contains('online')) score += 85;
  if (name.contains('google')) score += 70;
  if (name.contains('maged')) score += 60;
  if (name.contains('samantha') ||
      name.contains('karen') ||
      name.contains('daniel')) {
    score += 40;
  }
  return score;
}

/// تفعيل محرك نطق المتصفح داخل إيماءة المستخدم: في iOS يُشغَّل الصوت فقط
/// بعد تفاعل مباشر، لذا نُطلق جملة صامتة (volume=0) لفك الحجب — وإلا كان
/// كل كلام لاحق صامتاً (خاصة في كروم/سفاري على iPhone).
void _primeBrowserSpeech() {
  final synth = speechSynthesis;
  if (synth == null) return;
  try {
    if (synth.speaking) return;
    synth.cancel();
    final u = SpeechSynthesisUtterance(' ');
    u.volume = 0;
    u.lang = 'ar-SA';
    u.rate = 1.0;
    u.pitch = 1.0;
    synth.speak(u);
  } catch (_) {}
}

/// تقسيم النص الطويل إلى مقاطع قصيرة: بعض المتصفحات (iOS) توقف الكلام
/// أو تلغيه بعد فترة، فالنطق على دفعات يضمن إكمال الجملة كاملة.
List<String> _speechChunks(String text, {int maxChars = 180}) {
  final t = text.trim();
  if (t.isEmpty) return const [];
  if (t.length <= maxChars) return [t];
  final parts = t
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
  return chunks.isEmpty ? [t] : chunks;
}

Duration _speechTimeout(String chunk) {
  final seconds = (10 + chunk.length ~/ 12).clamp(20, 90);
  return Duration(seconds: seconds);
}

/// نطق النص صوتياً عبر المتصفح (مجاني، متعدد اللغات، بدون خادم).
/// يعمل على كل المتصفحات بما فيها iOS: ينتظر تحميل الأصوات، يختار
/// الأنسب للغة، ويقسّم النص الطويل إلى مقاطع حتى لا يُقطع الكلام.
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
  _initBrowserSpeech();
  synth.cancel();

  final lang = detectLang(text);
  await _ensureVoices(synth);
  final voice = _pickBestVoice(lang);

  var started = false;
  for (final chunk in _speechChunks(text)) {
    if (_activeEngine != SpeechEngine.browser) return;
    final completer = Completer<void>();
    final utterance = SpeechSynthesisUtterance(chunk);
    utterance.lang = lang;
    utterance.rate = rate;
    utterance.pitch = 1.0;
    if (voice != null) {
      try {
        utterance.voice = voice;
      } catch (_) {}
    }
    utterance.onend = ((SpeechSynthesisEvent _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    utterance.onerror = ((SpeechSynthesisEvent _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;

    synth.speak(utterance);
    if (!started) {
      started = true;
      onStart?.call();
    }
    // معالجة خلل iOS الشهير: استدعاء pause/resume فوراً بعد speak يمنع
    // صمت الكلام الطويل في سفاري/كروم على iPhone.
    if (_isIos) {
      try {
        synth.pause();
        synth.resume();
      } catch (_) {}
    }
    await completer.future.timeout(_speechTimeout(chunk), onTimeout: () {});
  }
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
/// المستخدم حتى لا يُحجب التشغيل المتدفق لاحقاً بسياسة التشغيل التلقائي،
/// ولفك حجب نطق المتصفح في iOS (بدون تفاعل مباشر لا يصدر صوت أبداً).
void warmUpAudio() {
  try {
    final ctx = _ensureAudioContext();
    if (ctx.state == 'suspended') {
      unawaited(ctx.resume().toDart);
    }
  } catch (_) {}
  _initBrowserSpeech();
  _primeBrowserSpeech();
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

// ---------- صوت إيدج الاحترافي المجاني (بديل فوري بلا مفتاح) ----------

/// نطق النص عبر خدمة مايكروسوفت إيدج المجانية (WebSocket بلا أي مفتاح)
/// بأصوات طبيعية احترافية للعربية والإنجليزية، ثم تشغيل الصوت (MP3) عبر
/// Web Audio API — ليعمل كنطق احترافي فوري عند فشل/انقطاع مفتاح Gemini.
Future<void> speakEdgeTts(
  String text, {
  double rate = 1.0,
  void Function()? onStart,
}) async {
  _stopStreamPlayback();
  _streamStop = false;
  _activeEngine = SpeechEngine.stream;
  final ctx = _ensureAudioContext();
  try {
    if (ctx.state == 'suspended') await ctx.resume().toDart;
  } catch (_) {}
  if (ctx.state == 'suspended') {
    throw Exception('سياسة التشغيل التلقائي أوقفت صوت إيدج');
  }

  final chunks = edgeTextChunks(text);
  if (chunks.isEmpty) throw Exception('لا يوجد نص للنطق');
  final voice = edgeVoiceForLang(detectLang(text));

  final ws = web.WebSocket(edgeTtsWsUrl());
  ws.binaryType = 'arraybuffer';

  final audio = <int>[];
  var receivedAudio = false;
  var failed = false;
  var currentTurn = Completer<void>();

  final msgSub = ws.onMessage.listen((ev) {
    final data = ev.data;
    if (data != null && data.isA<JSString>()) {
      if (edgeIsTurnEnd((data as JSString).toDart) && !currentTurn.isCompleted) {
        currentTurn.complete();
      }
    } else if (data != null && data.isA<JSArrayBuffer>()) {
      final payload =
          edgeAudioFromFrame((data as JSArrayBuffer).toDart.asUint8List());
      if (payload.isNotEmpty) {
        receivedAudio = true;
        audio.addAll(payload);
      }
    }
  });
  final errSub = ws.onError.listen((_) {
    failed = true;
    if (!currentTurn.isCompleted) {
      currentTurn.completeError(Exception('edge-ws-error'));
    }
  });
  final closeSub = ws.onClose.listen((_) {
    if (!currentTurn.isCompleted) currentTurn.complete();
  });

  try {
    await ws.onOpen.first.timeout(const Duration(seconds: 12));
    if (failed) throw Exception('تعذر الاتصال بخدمة إيدج');
    ws.send(edgeConfigMessage().toJS);
    for (final c in chunks) {
      if (_streamStop) return;
      ws.send(edgeSsmlMessage(voice: voice, text: c, rate: rate).toJS);
      var gotEnd = false;
      try {
        await currentTurn.future.timeout(const Duration(seconds: 40));
        gotEnd = true;
      } catch (_) {}
      if (_streamStop || failed) return;
      if (!gotEnd) break;
      currentTurn = Completer<void>();
    }
  } finally {
    await msgSub.cancel();
    await errSub.cancel();
    await closeSub.cancel();
    try {
      ws.close();
    } catch (_) {}
  }

  if (_streamStop) return;
  if (!receivedAudio || audio.isEmpty) {
    throw Exception('لم يصل صوت من خدمة إيدج');
  }
  final mp3 = Uint8List.fromList(audio);
  final ab = JSArrayBuffer(mp3.length);
  final view = JSUint8Array(ab);
  view.toDart.setAll(0, mp3);
  final decoded = await ctx
      .decodeAudioData(ab)
      .toDart
      .timeout(const Duration(seconds: 20));
  if (_streamStop) return;

  final src = ctx.createBufferSource();
  src.buffer = decoded;
  src.playbackRate.value = rate;
  src.connect(ctx.destination);
  final completer = Completer<void>();
  _streamCompleter = completer;
  src.onended = ((web.Event _) {
    if (!_streamStop && identical(src, _streamLast) && !completer.isCompleted) {
      completer.complete();
    }
  }).toJS;
  src.start();
  _streamLast = src;
  _streamSources.add(src);
  onStart?.call();
  await completer.future.timeout(const Duration(minutes: 5), onTimeout: () {});
  _streamSources.clear();
  _streamLast = null;
  _activeEngine = SpeechEngine.none;
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

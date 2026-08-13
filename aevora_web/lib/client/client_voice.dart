import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

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

/// تشغيل صوت احترافي مولّد من Gemini عبر عنصر صوت في المتصفح.
Future<void> speakProfessional(
  String text, {
  required String apiKey,
  double rate = 1.0,
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

/// نطق النص: يفضّل الصوت الاحترافي (Gemini) إن وُجد المفتاح، وإلا يعود للمتصفح.
Future<void> speakSmart(
  String text, {
  String? apiKey,
  double rate = 1.0,
}) async {
  if (apiKey != null && apiKey.trim().isNotEmpty) {
    try {
      await speakProfessional(text, apiKey: apiKey, rate: rate);
      return;
    } catch (_) {}
  }
  await speakText(text, rate: rate);
}

// ---------- واجهات Web Speech API (احتياطي مجاني بدون مفتاح) ----------

@JS()
external SpeechSynthesis? get speechSynthesis;

extension type SpeechSynthesis(JSObject _) implements JSObject {
  external void speak(SpeechSynthesisUtterance utterance);
  external void cancel();
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
Future<void> speakText(String text, {double rate = 1.0}) async {
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
  await completer.future.timeout(const Duration(seconds: 60), onTimeout: () {});
}

void stopSpeaking() {
  speechSynthesis?.cancel();
  _stopProfessionalPlayer();
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

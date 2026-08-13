import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:http/http.dart' as http;

import 'client_usage.dart';

// ---------- واجهات Web Speech API (لا تحتاج خادماً ولا مفتاحاً) ----------

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

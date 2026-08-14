import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'client_voice.dart';

/// مكوّن تشغيل الصوت على منصات الجوال (iOS/Android):
/// النطق الاحترافي يُولَّد عبر Gemini (غير متدفق) ويُشغَّل عبر audioplayers،
/// بينما «صوت المتصفح» (Web Speech) غير متاح على الجوال.
enum SpeechEngine { none, browser, stream }

SpeechEngine _activeEngine = SpeechEngine.none;

bool get activeEngineIsBrowser => false;
bool get activeEngineIsStream => _activeEngine == SpeechEngine.stream;

bool get isBrowserSpeechSupported => false;

AudioPlayer? _player;

void warmUpAudio() {}

/// صوت المتصفح غير متاح على الجوال — يعتمد النطق على مفتاح Gemini.
Future<void> speakText(
  String text, {
  double rate = 1.0,
  void Function()? onStart,
}) {
  throw UnsupportedError(
      'صوت المتصفح متاح في نسخة المتصفح فقط — استخدم النطق الاحترافي بمفتاح Gemini.');
}

/// النطق الاحترافي على الجوال: توليد كامل عبر Gemini ثم تشغيل WAV.
Future<void> speakProfessionalStreaming(
  String text, {
  required String apiKey,
  double rate = 1.0,
  void Function()? onStart,
}) async {
  final wav = await geminiTextToSpeech(apiKey: apiKey, text: text);
  final player = _player ??= AudioPlayer();
  await player.stop();
  try {
    await player.setPlaybackRate(rate);
  } catch (_) {}
  _activeEngine = SpeechEngine.stream;
  await player.play(BytesSource(wav));
  onStart?.call();

  final completer = Completer<void>();
  final sub = player.onPlayerComplete.listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  await completer.future
      .timeout(const Duration(minutes: 3), onTimeout: () {});
  await sub.cancel();
  _activeEngine = SpeechEngine.none;
}

void stopPlaybackNow() {
  _activeEngine = SpeechEngine.none;
  unawaited(_player?.stop());
}

Future<void> pauseActiveEngine() async {
  if (_activeEngine == SpeechEngine.stream) {
    await _player?.pause();
  }
}

Future<void> resumeActiveEngine() async {
  if (_activeEngine == SpeechEngine.stream) {
    await _player?.resume();
  }
}

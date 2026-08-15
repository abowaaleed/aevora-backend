import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

/// نطق النص عبر خدمة مايكروسوفت إيدج المجانية على الجوال (WebSocket عبر
/// dart:io بلا أي مفتاح) وتشغيل الصوت MP3 عبر audioplayers — نطق احترافي
/// فوري يعمل حتى من دون مفتاح Gemini.
Future<void> speakEdgeTts(
  String text, {
  double rate = 1.0,
  void Function()? onStart,
}) async {
  final chunks = edgeTextChunks(text);
  if (chunks.isEmpty) throw Exception('لا يوجد نص للنطق');
  final voice = edgeVoiceForLang(detectLang(text));
  final audio = <int>[];
  var receivedAudio = false;

  final ws = await WebSocket.connect(edgeTtsWsUrl())
      .timeout(const Duration(seconds: 12));
  final controller = StreamController<dynamic>.broadcast(sync: true);
  final sub = ws.listen(
    (msg) {
      if (!controller.isClosed) controller.add(msg);
    },
    onError: controller.addError,
    onDone: controller.close,
  );
  try {
    ws.add(edgeConfigMessage());
    for (final c in chunks) {
      ws.add(edgeSsmlMessage(voice: voice, text: c, rate: rate));
      final turn = Completer<void>();
      final lis = controller.stream.listen((msg) {
        if (msg is String) {
          if (edgeIsTurnEnd(msg) && !turn.isCompleted) turn.complete();
        } else if (msg is List<int>) {
          final payload = edgeAudioFromFrame(Uint8List.fromList(msg));
          if (payload.isNotEmpty) {
            receivedAudio = true;
            audio.addAll(payload);
          }
        }
      });
      try {
        await turn.future.timeout(const Duration(seconds: 40));
      } catch (_) {}
      await lis.cancel();
    }
  } finally {
    await sub.cancel();
    await ws.close();
    await controller.close();
  }

  if (!receivedAudio || audio.isEmpty) {
    throw Exception('لم يصل صوت من خدمة إيدج');
  }
  final player = _player ??= AudioPlayer();
  await player.stop();
  try {
    await player.setPlaybackRate(rate);
  } catch (_) {}
  _activeEngine = SpeechEngine.stream;
  await player.play(BytesSource(Uint8List.fromList(audio)));
  onStart?.call();

  final completer = Completer<void>();
  final sub2 = player.onPlayerComplete.listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  await completer.future
      .timeout(const Duration(minutes: 3), onTimeout: () {});
  await sub2.cancel();
  _activeEngine = SpeechEngine.none;
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

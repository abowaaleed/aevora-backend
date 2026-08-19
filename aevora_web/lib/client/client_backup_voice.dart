import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'client_usage.dart';

/// نظام الصوت الاحتياطي: يستخدم محرك النطق المدمج في الجهاز (Google TTS
/// على الأندرويد / AVSpeech على iOS) كخطة بديلة احترافية بعد نفاذ حصة
/// Gemini أو فشل Edge TTS — صوت بشري طبيعي بلا أي مفتاح وبلا حدود.
class BackupVoice {
  BackupVoice._();
  static final BackupVoice instance = BackupVoice._();

  FlutterTts? _tts;
  bool _ready = false;

  /// عدّاد الاستهلاك اليومي (أصوات احتياطية).
  int _todayCount = 0;
  int get todayCount => _todayCount;

  Future<void> init() async {
    if (_ready) return;
    if (kIsWeb) return;
    try {
      _tts = FlutterTts();
      await _tts!.setLanguage('en-US');
      await _tts!.setSpeechRate(0.48);
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);
      _ready = true;
      await _loadTodayCount();
    } catch (_) {
      _ready = false;
    }
  }

  bool get isReady => _ready && _tts != null;

  Future<bool> speak(
    String text, {
    double rate = 1.0,
    String? lang,
    void Function()? onStart,
  }) async {
    if (!isReady) return false;
    try {
      if (lang != null) await _tts!.setLanguage(lang);
      final completer = Completer<void>();
      _tts!.setCompletionHandler(() {
        if (!completer.isCompleted) completer.complete();
      });

      await _tts!.speak(text);
      onStart?.call();

      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {},
      );

      _todayCount++;
      await _saveTodayCount();
      await LocalUsage.recordBackupVoice();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    if (_tts != null) await _tts!.stop();
  }

  static const _countKey = 'backup_voice_count';
  static const _dateKey = 'backup_voice_date';

  String get _todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadTodayCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final date = prefs.getString(_dateKey);
      if (date == _todayStr) {
        _todayCount = prefs.getInt(_countKey) ?? 0;
      } else {
        _todayCount = 0;
      }
    } catch (_) {
      _todayCount = 0;
    }
  }

  Future<void> _saveTodayCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dateKey, _todayStr);
      await prefs.setInt(_countKey, _todayCount);
    } catch (_) {}
  }
}

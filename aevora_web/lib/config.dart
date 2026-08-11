import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// عنوان خادم الواجهة العامة.
/// عند البناء للاستضافة: flutter build web --dart-define=API_BASE=https://...onrender.com
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://localhost:8000',
);

const String appName = 'ايفورا';

class KeySettings {
  final String geminiKey;
  final String groqKey;
  final String email;
  final bool hasKeys;

  const KeySettings({
    this.geminiKey = '',
    this.groqKey = '',
    this.email = '',
    this.hasKeys = false,
  });
}

class AppStorage {
  static const _kGemini = 'aevora_gemini_key';
  static const _kGroq = 'aevora_groq_key';
  static const _kEmail = 'aevora_email';

  static Future<KeySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final gemini = prefs.getString(_kGemini) ?? '';
    final groq = prefs.getString(_kGroq) ?? '';
    final email = prefs.getString(_kEmail) ?? '';
    return KeySettings(
      geminiKey: gemini,
      groqKey: groq,
      email: email,
      hasKeys: gemini.trim().isNotEmpty || groq.trim().isNotEmpty,
    );
  }

  static Future<void> save({
    String geminiKey = '',
    String groqKey = '',
    String email = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGemini, geminiKey.trim());
    await prefs.setString(_kGroq, groqKey.trim());
    await prefs.setString(_kEmail, email.trim());
  }

  /// معرّف مستقر لكل مستخدم، مشتق من مفاتيحه حتى تتحدد هويته دون تسجيل.
  static String deriveUserId(KeySettings s) {
    final raw = [s.geminiKey, s.groqKey].where((k) => k.isNotEmpty).join('|');
    return sha256Hex(raw);
  }

  static String sha256Hex(String input) {
    // تنفيذ مبسّط: تجزئة منزلية عبر accumulate باستخدام إزاحات متعددة.
    // الغاية: معرّف ثابت وليس تشفيراً آمناً.
    final bytes = Uint8List.fromList(utf8.encode(input));
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    var h3 = 0xabcdef01;
    var h4 = 0x12345678;
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      h1 = ((h1 ^ b) * 16777619) & 0xFFFFFFFF;
      h2 = ((h2 + b) * 31) & 0xFFFFFFFF;
      h3 = (h3 * 33 + b) & 0xFFFFFFFF;
      h4 = (h4 ^ ((b << 3) | (b >> 5))) & 0xFFFFFFFF;
    }
    String hex(int v) => v.toRadixString(16).padLeft(8, '0');
    return (hex(h1) + hex(h2) + hex(h3) + hex(h4));
  }
}

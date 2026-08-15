import 'package:shared_preferences/shared_preferences.dart';

const String appName = 'ايفورا';

/// نسخة التطبيق الظاهرة في «الإعدادات» — تُرفَع يدوياً مع كل إصدار جديد
/// ليتمكن المستخدم من التحقق أن النسخة المنشورة قد تغيّرت.
const String appVersion = '1.4.1';

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

  /// صيغة السحابة (تُرفع مع الحساب لتعود في أي جهاز آخر يسجل دخولاً).
  Map<String, String> toCloudMap() => {
        'gemini': geminiKey.trim(),
        'groq': groqKey.trim(),
        'email': email.trim(),
      };
}

/// مفاتيح المستخدم محفوظة محلياً في متصفحه فقط (localStorage) —
/// ولا يُطلب أي خادم أو تسجيل.
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
}

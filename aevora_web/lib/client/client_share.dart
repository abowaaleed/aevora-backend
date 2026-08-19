import 'package:url_launcher/url_launcher.dart';

/// مشاركة نص عبر واتساب / تيليجرام / البريد.
/// إن كان النص طويلاً جداً لرابط التطبيق يُقصّ مع تنبيه في الرسالة.

const int _urlSafeLimit = 1800;

String _clip(String text) {
  final t = text.trim();
  if (t.length <= _urlSafeLimit) return t;
  return '${t.substring(0, _urlSafeLimit)}\n\n… (قُصّ النص لطوله — انسخ المحادثة كاملة من التطبيق)';
}

Future<bool> shareViaWhatsApp(String text) async {
  final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(_clip(text))}');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> shareViaTelegram(String text) async {
  final uri = Uri.parse(
      'https://t.me/share/url?url=&text=${Uri.encodeComponent(_clip(text))}');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> shareViaEmail(String text, {String subject = 'محادثة مع ايفورا'}) async {
  final uri = Uri.parse(
    'mailto:?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(_clip(text))}',
  );
  return launchUrl(uri);
}

import 'package:flutter/foundation.dart';

// ============================================================
// الإعدادات السحابية (Render)
// استبدل الرابط أدناه بالرابط الذي سيولّده Render لخدمتك،
// مثلاً: https://evora-backend.onrender.com
// ============================================================
const String _cloudBaseURL = 'https://evora-backend-v0fj.onrender.com';

// ضع true للعمل من أي مكان عبر السحابة،
// وضع false للعمل على الشبكة المحلية أثناء التطوير.
const bool _useCloudBackend = true;

// IP اللابتوب الحالي — يُستخدم فقط عند التطوير المحلي
const String _manualIP = '192.168.1.166';

String get backendUrl {
  if (kIsWeb) {
    return 'http://localhost:8000';
  } else {
    return _useCloudBackend ? _cloudBaseURL : 'http://$_manualIP:8000';
  }
}

String getFileUrl(String filename) => '$backendUrl/uploads/$filename';

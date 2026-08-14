/// واجهة «التصدير/المشاركة» الموحّدة:
/// - على المتصفح: `export_web.dart` (Web Share API + تنزيل مباشر).
/// - على الجوال (iOS/Android): `export_stub.dart` (نسخ عبر الحافظة).
library;

export 'export_stub.dart' if (dart.library.js_interop) 'export_web.dart';

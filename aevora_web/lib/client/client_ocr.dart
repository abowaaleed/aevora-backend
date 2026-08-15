/// واجهة «التعرف الضوئي على النصوص (OCR)» الموحّدة:
/// - على المتصفح: `ocr_web.dart` (tesseract.js — يعمل محلياً في المتصفح).
/// - على الجوال (iOS/Android): `ocr_stub.dart` (غير مدعوم حالياً).
library;

export 'ocr_stub.dart' if (dart.library.js_interop) 'ocr_web.dart';

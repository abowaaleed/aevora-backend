library;

/// OCR غير مدعوم على iOS/Android حالياً (يعمل على نسخة الويب).
Future<String> ocrImageBytes(List<int> bytes, String ext) {
  throw Exception('قراءة الصور (OCR) متاحة على نسخة الويب فقط حالياً.');
}

Future<bool> ocrAvailable() async => false;

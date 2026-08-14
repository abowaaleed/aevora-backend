/// حمّالة بايتات + اسم ملف، معاً في كائن واحد — مشتركة بين تنفيذي التخزين
/// (IndexedDB على المتصفح، SharedPreferences على الجوال).
class Uint8ListBytes {
  final List<int> bytes;
  final String filename;
  const Uint8ListBytes(this.bytes, this.filename);
}

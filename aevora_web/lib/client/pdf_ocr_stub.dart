/// تطبيق الجوال: لا يوجد تصيير صفحات PDF محلياً ولا OCR بعد — نُعيد رسالة
/// واضحة ليُترجمها المستدعي إلى رسالة عربية مفهومة.
Future<String> ocrPdfImages(
  List<int> bytes,
  int pageCount, {
  void Function(int page, int total)? onPage,
}) async {
  throw Exception(
      'التعرف الضوئي على الملفات الممسوحة ضوئياً غير متاح على الجوال — '
      'يُدعم على المتصفح. يمكنك رفع صور الصفحات مباشرة.');
}

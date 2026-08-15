/// واجهة التعرف الضوئي على ملفات PDF الممسوحة (صور صفحات بلا نص):
/// - على المتصفح: رسم كل صفحة عبر pdf.js ثم OCR عليها عبر tesseract.js.
/// - على الجوال: غير مدعوم حالياً (يُرمى استثناء برسالة واضحة).
library;

export 'pdf_ocr_stub.dart'
    if (dart.library.js_interop) 'pdf_ocr_web.dart';

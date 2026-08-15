import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// OCR عبر tesseract.js يعمل 100% في متصفح المستخدم (خصوصية كاملة).
/// يُحمَّل tesseract.min.js من CDN عند أول استخدام (يُخزَّن مؤقتاً).

const _tesseractCdn = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js';

Future<JSObject>? _loading;
JSObject? _cached;

Future<JSObject> _loadTesseract() {
  final existing = _cached;
  if (existing != null) return Future.value(existing);
  return _loading ??= _doLoad();
}

Future<JSObject> _doLoad() async {
  final inPage =
      (web.window as JSObject).getProperty('Tesseract'.toJS) as JSObject?;
  if (inPage != null) {
    _cached = inPage;
    return inPage;
  }

  final completer = Completer<JSObject>();
  final script = web.document.createElement('script') as web.HTMLScriptElement;
  script.src = _tesseractCdn;
  script.async = true;
  script.onload = ((JSAny _) {
    final t =
        (web.window as JSObject).getProperty('Tesseract'.toJS) as JSObject?;
    if (t != null) {
      _cached = t;
      completer.complete(t);
    } else {
      completer.completeError(Exception('فشل تحميل مكتبة OCR.'));
    }
  }).toJS;
  script.onerror = ((JSAny _) {
    completer.completeError(
        Exception('تعذّر تحميل مكتبة OCR من الإنترنت. تأكد من اتصالك ثم أعد المحاولة.'));
  }).toJS;
  web.document.head?.appendChild(script);
  try {
    final result = await completer.future;
    _cached = result;
    return result;
  } finally {
    _loading = null;
  }
}

String _mimeFor(String ext) {
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'bmp':
      return 'image/bmp';
    default:
      return 'image/jpeg';
  }
}

/// استخراج النص من صورة (PNG/JPG/GIF/BMP/WebP) عبر OCR محلي.
Future<String> ocrImageBytes(List<int> bytes, String ext) async {
  final tesseract = await _loadTesseract();
  final dataUrl = 'data:${_mimeFor(ext)};base64,${base64Encode(bytes)}';

  final workerPromise = tesseract.callMethod<JSPromise>('createWorker'.toJS,
      ('ara+eng').toJS, 1.toJS, JSObject());
  final worker = (await workerPromise.toDart) as JSObject;

  try {
    final result = await (worker.callMethod<JSPromise>(
            'recognize'.toJS, dataUrl.toJS))
        .toDart;
    final data = (result as JSObject).getProperty('data'.toJS) as JSObject;
    final text = data.getProperty('text'.toJS) as JSString;
    return text.toDart;
  } finally {
    try {
      await (worker.callMethod<JSPromise>('terminate'.toJS)).toDart;
    } catch (_) {}
  }
}

/// هل المتصفح جاهز للـ OCR؟ (يُحمّل المكتبة عند النداء الأول).
Future<bool> ocrAvailable() async {
  try {
    await _loadTesseract();
    return true;
  } catch (_) {
    return false;
  }
}

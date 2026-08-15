import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'client_ocr.dart' as ocr;

/// التعرف الضوئي على ملفات PDF الممسوحة ضوئياً (صور صفحات بلا نص قابل
/// للاستخراج):
/// 1) تحميل pdf.js من CDN ورسم كل صفحة على لوحة رسم داخل المتصفح.
/// 2) تحويل اللوحة إلى صورة JPEG وتغذيتها لنفس محرك OCR المستخدم للصور
///    (tesseract.js) ليُستخرج نص الصفحة.
///
/// كل شيء يعمل محلياً 100% في المتصفح — لا يُرسل الملف لأي خادم خارجي.
/// [onPage] يُستدعى بعد كل صفحة (رقم الصفحة، الإجمالي) لتحديث الواجهة.

const _pdfJsCdn =
    'https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.min.js';
const _pdfWorkerCdn =
    'https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.worker.min.js';

Future<JSObject>? _loading;
JSObject? _cached;

Future<JSObject> _loadPdfJs() {
  final existing = _cached;
  if (existing != null) return Future.value(existing);
  return _loading ??= _doLoad();
}

Future<JSObject> _doLoad() async {
  final inPage =
      (web.window as JSObject).getProperty('pdfjsLib'.toJS) as JSObject?;
  if (inPage != null) {
    _cached = inPage;
    return inPage;
  }

  final completer = Completer<JSObject>();
  final script = web.document.createElement('script') as web.HTMLScriptElement;
  script.src = _pdfJsCdn;
  script.async = true;
  script.onload = ((JSAny _) {
    final lib =
        (web.window as JSObject).getProperty('pdfjsLib'.toJS) as JSObject?;
    if (lib == null) {
      completer.completeError(Exception('فشل تحميل مكتبة معالجة PDF.'));
      return;
    }
    try {
      final workers = lib.getProperty('GlobalWorkerOptions'.toJS) as JSObject;
      workers.setProperty('workerSrc'.toJS, _pdfWorkerCdn.toJS);
    } catch (_) {}
    _cached = lib;
    completer.complete(lib);
  }).toJS;
  script.onerror = ((JSAny _) {
    completer.completeError(Exception(
        'تعذّر تحميل مكتبة معالجة PDF من الإنترنت. تأكد من اتصالك ثم أعد المحاولة.'));
  }).toJS;
  web.document.head?.appendChild(script);
  try {
    return await completer.future;
  } finally {
    _loading = null;
  }
}

/// استخراج نص كل صفحة من ملف PDF ممسوح ضوئياً عبر رسم الصفحة وOCR عليها.
/// يُرمى استثناء إن تعذّر تحميل pdf.js/بدء قراءة المستند؛ أما فشل صفحة
/// واحدة (رسم أو OCR) فلا يوقف بقية الصفحات.
Future<String> ocrPdfImages(
  List<int> bytes,
  int pageCount, {
  void Function(int page, int total)? onPage,
}) async {
  final pdfjs = await _loadPdfJs();

  final params = JSObject();
  params.setProperty('data'.toJS, Uint8List.fromList(bytes).toJS as JSAny);
  final loadTask = pdfjs.callMethod<JSPromise>('getDocument'.toJS, params);
  final pdf = (await loadTask.toDart.timeout(const Duration(seconds: 45)))
      as JSObject;
  try {
    final numPages =
        (pdf.getProperty('numPages'.toJS) as JSNumber?)?.toDartInt ??
            pageCount;
    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    final ctx = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    final sb = StringBuffer();

    for (var i = 1; i <= numPages; i++) {
      onPage?.call(i, numPages);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final page =
          (await (pdf.callMethod<JSPromise>('getPage'.toJS, i.toJS)).toDart)
              as JSObject;
      try {
        final baseViewport = page.callMethod<JSObject>(
            'getViewport'.toJS, ({'scale': 1.0}).jsify());
        final baseW =
            (baseViewport.getProperty('width'.toJS) as JSNumber?)?.toDartDouble ??
                0;
        final baseH =
            (baseViewport.getProperty('height'.toJS) as JSNumber?)?.toDartDouble ??
                0;
        var scale = 2.0;
        if (baseW > 0 && baseW * scale > 4096) scale = 4096 / baseW;
        if (baseH > 0 && baseH * scale > 4096) scale = math.min(scale, 4096 / baseH);
        final viewport = page.callMethod<JSObject>(
            'getViewport'.toJS, ({'scale': scale}).jsify());
        canvas.width =
            (viewport.getProperty('width'.toJS) as JSNumber?)?.toDartInt ?? 0;
        canvas.height =
            (viewport.getProperty('height'.toJS) as JSNumber?)?.toDartInt ?? 0;
        if (canvas.width <= 0 || canvas.height <= 0) continue;

        final renderParams = JSObject();
        renderParams.setProperty('canvasContext'.toJS, ctx);
        renderParams.setProperty('viewport'.toJS, viewport);
        await (page.callMethod<JSPromise>('render'.toJS, renderParams)).toDart;

        final dataUrl = canvas.callMethod<JSString>(
            'toDataURL'.toJS, 'image/jpeg'.toJS, 0.9.toJS);
        final b64 = dataUrl.toDart.split(',').last;
        final imgBytes = base64Decode(b64);
        final pageText = await ocr.ocrImageBytes(imgBytes, 'jpg');
        if (pageText.trim().isNotEmpty) {
          sb.writeln(pageText.trim());
          sb.writeln('');
        }
      } catch (_) {
        // فشل في صفحة واحدة (رسم/تحويل/OCR) — نكمل بقية الصفحات بدلاً من
        // إسقاط الملف كاملاً، ويُخزَّن ما نجح استخراجه.
      } finally {
        try {
          page.callMethod<JSAny>('cleanup'.toJS);
        } catch (_) {}
      }
    }
    return sb.toString().trim();
  } finally {
    try {
      pdf.callMethod<JSAny>('destroy'.toJS);
    } catch (_) {}
  }
}

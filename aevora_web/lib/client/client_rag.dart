import 'dart:math' as math;
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'client_ocr.dart' as ocr;
import 'client_storage.dart';
import 'pdf_ocr.dart' as pdf_ocr;
import 'text_arabic.dart';
import 'text_files.dart';

/// شريحة من مستند استُخرجت محلياً في المتصفح.
class RagChunk {
  final String file;
  final String text;
  RagChunk(this.file, this.text);
}

const _maxFileText = 2000000;
const _dim = 256;

const _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'};

/// الصيغ المقبولة في نافذة رفع الملفات.
const allowedUploadExtensions = ['pdf', 'docx', 'txt', 'png', 'jpg', 'jpeg'];

/// نص يوضّح الصيغ المدعومة لرفعه في واجهة المستخدم.
const acceptedFormatsLabel = 'الصيغ المدعومة: PDF · Word (.docx) · TXT · صور (PNG/JPG)';

/// استخراج النص محلياً (بدون أي خادم) من:
/// PDF / Word (.docx) / TXT / صور (OCR على الويب).
/// الصيغ المدعومة للرفع: pdf, docx, txt, png, jpg, jpeg, gif, bmp, webp.
/// [onPage] يُستدعى بعد كل صفحة PDF (رقم الصفحة، الإجمالي) لتحديث الواجهة.
Future<String> extractText(
  String filename,
  List<int> bytes, {
  void Function(int page, int total)? onPage,
}) async {
  final name = filename.toLowerCase();
  final ext = name.contains('.') ? name.split('.').last : '';

  if (name.endsWith('.txt')) return decodeTextFile(bytes);
  if (name.endsWith('.pdf')) return _extractPdfText(bytes, onPage: onPage);
  if (name.endsWith('.docx')) return docxToText(bytes);
  if (name.endsWith('.doc')) {
    throw Exception(
        'ملفات Word القديمة (.doc) غير مدعومة — احفظ الملف بصيغة .docx ثم أعد الرفع.');
  }
  if (_imageExts.contains(ext)) {
    final text = await ocr.ocrImageBytes(bytes, ext).catchError((e) {
      throw Exception(
          'تعذّرت قراءة الصورة: ${e is Exception ? e.toString().replaceFirst('Exception: ', '') : e}');
    });
    if (text.trim().isEmpty) {
      throw Exception('لم يتعرّف الـ OCR على أي نص في هذه الصورة.');
    }
    return text;
  }
  throw Exception(
      'الصيغة غير مدعومة. المدعوم: PDF، Word (.docx)، TXT، وصور (PNG/JPG).');
}

/// استخراج نص PDF مع إعادة بناء اتجاه القراءة للعربية (RTL):
/// نجمع الحروف بترتيب مواضعها الأفقية الحقيقية (ترتيب بصري) ثم
/// نحوّلها إلى الترتيب المنطقي الصحيح عبر `visualToLogical`.
///
/// العملية ثقيلة على ملفات كبيرة، لذلك نُطلق حلقة الأحداث (await) بعد كل
/// صفحة — وإلا تجمّدت الواجهة تماماً وظل شريط التقدم «عالقاً» دون رسم.
Future<String> _extractPdfText(
  List<int> bytes, {
  void Function(int page, int total)? onPage,
}) async {
  await Future<void>.delayed(const Duration(milliseconds: 16));
  final doc = PdfDocument(inputBytes: Uint8List.fromList(bytes));
  try {
    final extractor = PdfTextExtractor(doc);
    final pageCount = doc.pages.count;
    final sb = StringBuffer();

    for (var p = 0; p < pageCount; p++) {
      onPage?.call(p + 1, pageCount);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final lines =
          extractor.extractTextLines(startPageIndex: p, endPageIndex: p);
      for (final line in lines) {
        final isArabicLine = containsArabic(line.text);
        if (!isArabicLine) {
          final t = line.text.trim();
          if (t.isNotEmpty) sb.writeln(t);
          continue;
        }

        // إعادة بناء السطر بالترتيب البصري (حسب موضع X لكل حرف).
        final glyphs = <({String ch, double left, double right})>[];
        for (final word in line.wordCollection) {
          for (final g in word.glyphs) {
            final left = g.bounds.left;
            final right = left + g.bounds.width;
            glyphs.add((ch: g.text, left: left, right: right));
          }
        }
        if (glyphs.isEmpty) {
          final t = line.text.trim();
          if (t.isNotEmpty) sb.writeln(t);
          continue;
        }
        glyphs.sort((a, b) => a.left.compareTo(b.left));

        final lineH = line.bounds.height > 0 ? line.bounds.height : line.fontSize;
        final threshold = 0.4 * lineH;
        final visual = StringBuffer();
        var lastRight = double.negativeInfinity;
        for (final g in glyphs) {
          final isSpaceGlyph = g.ch.trim().isEmpty && g.right - g.left > 0.1;
          if (!isSpaceGlyph &&
              lastRight != double.negativeInfinity &&
              g.left - lastRight > threshold) {
            visual.write(' ');
          }
          if (isSpaceGlyph) {
            visual.write(' ');
          } else if (g.ch.trim().isNotEmpty) {
            visual.write(g.ch);
          }
          if (g.right > lastRight) lastRight = g.right;
        }
        final logical = visualToLogical(visual.toString());
        if (logical.trim().isNotEmpty) sb.writeln(logical);
      }
    }

    final result = sb.toString().trim();
    if (result.isEmpty && pageCount > 0) {
      // ملف ممسوح ضوئياً (صور صفحات بلا نص قابل للاستخراج): نرسم كل صفحة
      // ونتعرف عليها نصياً عبر OCR داخل المتصفح ليصبح النص قابلاً للبحث
      // في المحادثة. لو تعذّر (غير مدعوم/بلا إنترنت) نعطي رسالة واضحة.
      String? ocrText;
      try {
        ocrText = await pdf_ocr.ocrPdfImages(bytes, pageCount, onPage: onPage);
      } catch (_) {
        ocrText = null;
      }
      if (ocrText != null && ocrText.trim().isNotEmpty) return ocrText.trim();
      throw Exception(
          'هذا الملف يبدو ممسوحاً ضوئياً (صور فقط) ولم يتعرّف OCR على نص فيه. '
          'يمكنك رفع صور الصفحات مباشرة.');
    }
    return result;
  } finally {
    doc.dispose();
  }
}

List<String> chunkText(String text, {int maxChunk = 1200, int overlap = 150}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return [];
  final chunks = <String>[];
  var start = 0;
  while (start < normalized.length) {
    var end = math.min(start + maxChunk, normalized.length);
    if (end < normalized.length) {
      final cut = normalized.lastIndexOf('. ', end);
      if (cut > start + maxChunk ~/ 2) end = cut + 1;
    }
    chunks.add(normalized.substring(start, end).trim());
    if (end >= normalized.length) break;
    start = end - overlap;
  }
  return chunks;
}

void _addHash(Float64List v, int h, double weight) {
  final idx = h.abs() % _dim;
  v[idx] += (h.isNegative ? -weight : weight);
}

/// متجه محلي (Hashing TF) يُحسب في المتصفح مباشرة — خصوصية كاملة وبلا تكلفة.
List<double> embedText(String text) {
  final v = Float64List(_dim);
  final words = text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty)
      .toList();
  for (final w in words) {
    _addHash(v, w.hashCode, 1.0);
    if (w.length > 3) {
      for (var i = 0; i <= w.length - 3; i++) {
        _addHash(v, w.substring(i, i + 3).hashCode, 0.7);
      }
    }
  }
  var norm = 0.0;
  for (final x in v) {
    norm += x * x;
  }
  if (norm > 0) {
    final inv = 1.0 / math.sqrt(norm);
    for (var i = 0; i < _dim; i++) {
      v[i] *= inv;
    }
  }
  return v.toList();
}

double _cosine(List<double> a, List<double> b) {
  final n = math.min(a.length, b.length);
  var dot = 0.0;
  for (var i = 0; i < n; i++) {
    dot += a[i] * b[i];
  }
  return dot;
}

/// فهرسة ملف محلياً: استخراج النص + تقطيع + توليد المتجهات + حفظ في IndexedDB.
/// يُبلَّغ التقدم عبر [onProgress] (نسبة 0..1 واسم المرحلة) لتحديث الواجهة.
Future<void> indexLocalFile(
  String filename,
  List<int> bytes, {
  void Function(double fraction, String stage)? onProgress,
}) async {
  onProgress?.call(0.02, 'استخراج النص من الملف...');
  // إتاحة فرصة للواجهة لرسم المرحلة قبل بدء العمل الثقيل (فك ضغط PDF ...)
  // وإلا بقي الشريط «عالقاً» لأن خيط الواجهة مشغول بالمعالجة.
  await Future<void>.delayed(const Duration(milliseconds: 16));
  final raw = await extractText(filename, bytes, onPage: (page, total) {
    onProgress?.call(
      0.02 + 0.58 * (page / total),
      'قراءة الصفحة $page من $total...',
    );
  });
  final text = raw.length > _maxFileText ? raw.substring(0, _maxFileText) : raw;
  onProgress?.call(0.65, 'حفظ الملف محلياً...');
  await Future<void>.delayed(const Duration(milliseconds: 16));

  await LocalDb.saveFileMeta({
    'id': filename,
    'name': filename,
    'size': bytes.length,
    'addedAt': DateTime.now().millisecondsSinceEpoch,
    'text': text,
    'status': 'indexed',
  });
  await LocalDb.saveFileBlob(filename, Uint8ListBytes(bytes, filename));
  await LocalDb.clearChunksForFile(filename);

  final chunks = chunkText(text);
  if (chunks.isEmpty) {
    onProgress?.call(1.0, 'اكتمل');
    return;
  }
  for (var i = 0; i < chunks.length; i++) {
    await LocalDb.saveChunk({
      'id': '$filename::$i',
      'file': filename,
      'idx': i,
      'text': chunks[i],
      'vec': embedText(chunks[i]),
    });
    // تحديث الشريط كل بضعة شرائح (وليس كل واحدة) مع إطلاق حلقة الأحداث
    // حتى لا يتكدّس الرسم وتظل الواجهة سريعة أثناء الفهرسة.
    if (i % 4 == 0 || i == chunks.length - 1) {
      onProgress?.call(
        0.65 + 0.35 * ((i + 1) / chunks.length),
        'فهرسة النص للبحث (${i + 1} من ${chunks.length})...',
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }
  onProgress?.call(1.0, 'اكتمل');
}

Future<bool> hasFiles() async => (await LocalDb.listFiles()).isNotEmpty;

Future<int> fileCount() async => (await LocalDb.listFiles()).length;

/// البحث المحلي: إرجاع أفضل الشرائح تطابقاً للسؤال.
Future<List<RagChunk>> retrieveChunks(String query, {int k = 6}) async {
  final qv = embedText(query);
  final all = await LocalDb.allChunks();
  if (all.isEmpty) return [];

  final scored = <({double score, RagChunk chunk})>[];
  for (final c in all) {
    final vec = (c['vec'] as List? ?? const [])
        .cast<num>()
        .map((e) => e.toDouble())
        .toList();
    if (vec.isEmpty) continue;
    scored.add((
      score: _cosine(qv, vec),
      chunk: RagChunk(c['file']?.toString() ?? '', c['text']?.toString() ?? ''),
    ));
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.take(k).map((s) => s.chunk).toList();
}

/// بناء نص السياق الذي يُحقن في نظام المساعد.
String buildContextPrompt(List<RagChunk> chunks) {
  if (chunks.isEmpty) return '';
  final sb = StringBuffer('مقتطفات من مستنداتك المرفوعة (استخدمها عند الإجابة):\n');
  for (var i = 0; i < chunks.length; i++) {
    sb.writeln('[$i] (من «${chunks[i].file}»): ${chunks[i].text}');
  }
  return sb.toString();
}

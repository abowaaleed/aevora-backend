import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'client_storage.dart';

/// شريحة من مستند استُخرجت محلياً في المتصفح.
class RagChunk {
  final String file;
  final String text;
  RagChunk(this.file, this.text);
}

const _maxFileText = 2000000;
const _dim = 256;

/// استخراج نص PDF أو TXT محلياً (بدون أي خادم).
Future<String> extractText(String filename, List<int> bytes) async {
  final name = filename.toLowerCase();
  if (name.endsWith('.txt')) {
    return utf8.decode(bytes, allowMalformed: true);
  }
  if (name.endsWith('.pdf')) {
    final doc = PdfDocument(inputBytes: Uint8List.fromList(bytes));
    try {
      return PdfTextExtractor(doc).extractText();
    } finally {
      doc.dispose();
    }
  }
  throw Exception('الصيغة غير مدعومة محلياً. المدعوم: PDF وTXT فقط.');
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
Future<void> indexLocalFile(String filename, List<int> bytes) async {
  final raw = await extractText(filename, bytes);
  final text = raw.length > _maxFileText ? raw.substring(0, _maxFileText) : raw;

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
  for (var i = 0; i < chunks.length; i++) {
    await LocalDb.saveChunk({
      'id': '$filename::$i',
      'file': filename,
      'idx': i,
      'text': chunks[i],
      'vec': embedText(chunks[i]),
    });
  }
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

import 'package:flutter_test/flutter_test.dart';

import 'package:aevora_web/client/client_rag.dart';

void main() {
  test('embedText produces normalized vectors', () {
    final v1 = embedText('طابعة Bambu Lab A1 احترافية');
    final v2 = embedText('طابعة Bambu Lab A1 احترافية');
    final v3 = embedText('وصفة كيك الشوكولاتة');
    expect(v1.length, 256);
    expect(v1, v2);
    expect(_cosineSim(v1, v3), lessThan(0.5));
    expect(_cosineSim(v1, v2), greaterThan(0.99));
  });

  test('chunkText splits long text with overlap', () {
    final long = List.generate(200, (i) => 'كلمة $i').join(' ');
    final chunks = chunkText(long);
    expect(chunks.length, greaterThan(1));
    expect(chunks.every((c) => c.trim().isNotEmpty), isTrue);
  });
}

double _cosineSim(List<double> a, List<double> b) {
  var dot = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
  }
  return dot;
}

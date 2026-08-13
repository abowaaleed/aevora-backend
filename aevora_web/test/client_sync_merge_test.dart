import 'package:flutter_test/flutter_test.dart';

import 'package:aevora_web/client/client_sync.dart';

void main() {
  test('merge keeps local messages even when cloud is older', () {
    final local = [
      {'id': 'm1', 'role': 'user', 'text': 'سؤال قديم'},
      {'id': 'm2', 'role': 'user', 'text': 'سؤال كتبته للتو'},
    ];
    final cloud = [
      {'id': 'm1', 'role': 'user', 'text': 'سؤال قديم'},
    ];
    final merged = mergeChatMessages(local, cloud);
    expect(merged.length, 2);
    expect(merged.map((m) => m['id']), contains('m2'));
  });

  test('merge adds cloud-only messages to a fresh device', () {
    final cloud = [
      {'id': 'c1', 'role': 'model', 'text': 'جواب من جهاز آخر'},
    ];
    final merged = mergeChatMessages(null, cloud);
    expect(merged.length, 1);
    expect(merged.first['id'], 'c1');
    expect(merged.first['text'], 'جواب من جهاز آخر');
  });

  test('merge dedupes identical ids and caps at 100 messages', () {
    final local = [
      for (var i = 0; i < 60; i++)
        {'id': 'l$i', 'role': 'user', 'text': 'محلي $i'},
    ];
    final cloud = [
      ...local,
      for (var i = 0; i < 80; i++)
        {'id': 'c$i', 'role': 'user', 'text': 'سحابي $i'},
    ];
    final merged = mergeChatMessages(local, cloud);
    expect(merged.length, 100);
    expect(merged.map((m) => m['id']).toSet().length, 100);
    expect(merged.map((m) => m['id']), contains('c79'));
  });

  test('merge skips empty text and normalizes legacy messages', () {
    final local = [
      {'role': 'user', 'text': 'بدون معرف'},
    ];
    final cloud = [
      {'role': 'user', 'text': 'بدون معرف'},
      {'role': 'model', 'text': '   '},
    ];
    final merged = mergeChatMessages(local, cloud);
    expect(merged.length, 1);
    expect(merged.first['id'], isNotEmpty);
    expect(merged.first['role'], 'user');
  });
}

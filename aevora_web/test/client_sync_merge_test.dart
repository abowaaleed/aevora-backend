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

  test('persist-style merge never shrinks stored history', () {
    // محاكاة سباق فتح التطبيق: المحفوظ يحتوي التاريخ كاملاً، والواجهة
    // لم تكتمل بعد فتحمل الرسالة الجديدة فقط — الدمج يجب ألا يمسح التاريخ.
    final existing = [
      {'id': 'm1', 'role': 'user', 'text': 'السؤال الأول'},
      {'id': 'r1', 'role': 'model', 'text': 'الجواب الأول'},
      {'id': 'm2', 'role': 'user', 'text': 'السؤال الثاني'},
    ];
    final inMemory = [
      {'id': 'm3', 'role': 'user', 'text': 'رسالة جديدة للتو'},
    ];
    final merged = mergeChatMessages(existing, inMemory);
    expect(merged.length, 4);
    expect(merged.map((m) => m['id']), containsAll(['m1', 'r1', 'm2', 'm3']));
    expect(merged.last['id'], 'm3');
  });

  test('push-style merge unions local with richer cloud', () {
    // محاكاة رفع من جهاز بقائمة قديمة: السحابة أغنى — الدمج يحتفظ بالكل.
    final local = [
      {'id': 'm1', 'role': 'user', 'text': 'سؤال قديم'},
    ];
    final cloud = [
      {'id': 'm1', 'role': 'user', 'text': 'سؤال قديم'},
      {'id': 'm2', 'role': 'user', 'text': 'سؤال من جهاز آخر'},
      {'id': 'r2', 'role': 'model', 'text': 'جوابه'},
    ];
    final merged = mergeChatMessages(local, cloud);
    expect(merged.length, 3);
    expect(merged.map((m) => m['id']), containsAll(['m1', 'm2', 'r2']));
  });

  test('empty local files do not wipe cloud files', () {
    final cloud = [
      {'id': 'a.pdf', 'name': 'a.pdf', 'size': 10},
    ];
    final merged = mergeFileLists([], cloud, <String>{});
    expect(merged.length, 1);
    expect(merged.first['name'], 'a.pdf');
  });

  test('deleted names stay out of merged files', () {
    final local = [
      {'id': 'b.pdf', 'name': 'b.pdf'},
    ];
    final cloud = [
      {'id': 'a.pdf', 'name': 'a.pdf'},
      {'id': 'b.pdf', 'name': 'b.pdf'},
    ];
    final merged = mergeFileLists(local, cloud, {'a.pdf'});
    expect(merged.map((m) => m['name']), ['b.pdf']);
  });
}

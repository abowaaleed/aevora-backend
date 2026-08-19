import 'package:aevora_web/client/client_reminder_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses evening appointment', () {
    final p = parseChatReminder('ذكرني بموعد الساعة العاشرة مساءً');
    expect(p, isNotNull);
    expect(p!.hour, 22);
    expect(p.title, contains('موعد'));
  });

  test('parses numeric time', () {
    final p = parseChatReminder('ذكرني بزيارة الساعة 8 صباحا');
    expect(p, isNotNull);
    expect(p!.hour, 8);
    expect(p.title.toLowerCase(), contains('زيارة'));
  });

  test('ignores unrelated chat', () {
    expect(parseChatReminder('ما رأيك في هذا المستند؟'), isNull);
  });
}

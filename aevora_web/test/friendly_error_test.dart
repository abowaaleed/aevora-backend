import 'package:aevora_web/client/client_llm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('friendlyError يزيل بادئة Exception التقنية', () {
    final msg = friendlyError(Exception('استُنفدت حصة محادثات Gemini اليوم'));
    expect(msg, isNot(contains('خطأ')));
    expect(msg, isNot(contains('Exception')));
    expect(msg, isNotEmpty);
  });

  test('friendlyError يلطّف خطأ الحصة اليومية برسالة ودّية', () {
    final msg = friendlyError(Exception(
        'استُنفدت حصة محادثات Gemini اليوم (1,500 طلب). تُعاد الحصة '
        'تلقائياً عند منتصف الليل بتوقيت المحيط الهادئ.'));
    expect(msg, contains('منتصف الليل'));
    expect(msg, isNot(contains('Exception')));
  });

  test('friendlyError يلطّف ازدحام النموذج', () {
    final msg = friendlyError(Exception('خدمة Gemini مزدحمة حالياً (ازدحام مؤقت).'));
    expect(msg, contains('مشغولة'));
  });

  test('friendlyError يلطّف حد الطلبات في الدقيقة', () {
    final msg = friendlyError(
        Exception('تجاوزت حد الطلبات في الدقيقة (حوالي 10 طلبات/دقيقة).'));
    expect(msg, contains('دقيقة'));
  });

  test('friendlyError يلطّف المفتاح غير الصالح', () {
    final msg = friendlyError(Exception('مفتاح Gemini غير صالح أو محذوف.'));
    expect(msg, contains('الإعدادات'));
  });

  test('friendlyError يلطّف الأخطاء العامة بلا نص تقني', () {
    final msg = friendlyError(Exception('some random technical stack'));
    expect(msg, isNot(contains('Exception')));
    expect(msg, isNotEmpty);
  });

  test('friendlyError يتعامل مع رسالة فارغة', () {
    final msg = friendlyError(Exception(''));
    expect(msg, isNotEmpty);
  });
}

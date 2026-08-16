import 'package:aevora_web/client/client_llm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RPM quota error is NOT reported as daily quota (the bug)', () {
    // رسالة Google الفعلية لحد «في الدقيقة» تحتوي كلمة «quota» — كانت
    // تُفسَّر خطأً على أنها استنفاد الحصة اليومية.
    final body = '{"error":{"message":"Quota exceeded for metric '
        '\'generate_content_requests_per_minute_per_project\' and limit '
        '\'10 per minute\' per minute. Please retry.","status":"RESOURCE_EXHAUSTED"}}';
    final msg = extractGeminiError(body, 429);
    expect(msg, contains('في الدقيقة'));
    expect(msg, isNot(contains('استُنفدت حصة محادثات Gemini اليوم')));
  });

  test('RPM error with underscores is classified as per-minute', () {
    final body = '{"error":{"message":"Quota exceeded for metric '
        'generate_content_requests_per_minute_per_project limit 10 per minute"}}';
    final msg = extractGeminiError(body, 429);
    expect(msg, contains('في الدقيقة'));
  });

  test('daily quota error is classified as daily', () {
    final body = '{"error":{"message":"Quota exceeded for metric '
        '\'generate_content_requests_per_day_per_project\' and limit '
        '\'1500 per day\' per day.","status":"RESOURCE_EXHAUSTED"}}';
    final msg = extractGeminiError(body, 429);
    expect(msg, contains('استُنفدت حصة محادثات Gemini اليوم'));
  });

  test('resource has been exhausted maps to daily quota', () {
    final body = '{"error":{"message":"Resource has been exhausted '
        '(e.g. check quota).","status":"RESOURCE_EXHAUSTED"}}';
    final msg = extractGeminiError(body, 429);
    expect(msg, contains('استُنفدت حصة محادثات Gemini اليوم'));
  });

  test('high demand maps to congestion not daily quota', () {
    final body = '{"error":{"message":"The model is overloaded. Please try '
        'again later.","status":"UNAVAILABLE"}}';
    final msg = extractGeminiError(body, 429);
    expect(msg, contains('مزدحمة'));
    expect(msg, isNot(contains('استُنفدت حصة محادثات Gemini اليوم')));
  });

  test('invalid api key maps to settings guidance', () {
    final body =
        '{"error":{"message":"API key not valid. Please pass a valid API key."}}';
    final msg = extractGeminiError(body, 400);
    expect(msg, contains('مفتاح Gemini غير صالح'));
  });

  test('friendlyError softens the classified daily-quota message', () {
    final e = Exception('استُنفدت حصة محادثات Gemini اليوم (1,500 طلب).');
    expect(friendlyError(e), isNot(contains('Exception')));
    expect(friendlyError(e), contains('منتصف الليل'));
  });

  test('friendlyError softens the per-minute message', () {
    final e = Exception('تجاوزت حد الطلبات في الدقيقة (حوالي 10 طلبات/دقيقة).');
    final msg = friendlyError(e);
    expect(msg, isNot(contains('Exception')));
    expect(msg, contains('دقيقة'));
  });
}

/// إعدادات الدفع الإلكتروني في ايفورا.
///
/// لتفعيل الاشتراكات الفعلية:
/// 1) أنشئ حساب تاجر في بوابة دفع سعودية/خليجية — الموصى بها Tap
///    (https://tap.company) لدعم mada + Apple Pay + STC Pay + الفوترة المتكررة،
///    أو Moyasar، وللدفع الدولي Stripe.
/// 2) ضع المفتاح العام هنا (يُنشر بأمان داخل التطبيق).
/// 3) انشر وظائف `functions/` على Cloud Functions وضع المفتاح السري هناك
///    (لا يُنشر المفتاح السري أبداً في التطبيق).
/// ما دامت القيم النموذجية موجودة تظهر أزرار الاشتراك بحالة «قريباً».
class PaymentConfig {
  PaymentConfig._();

  /// البوابة النشطة حالياً: 'tap' | 'moyasar' | 'stripe'.
  static const String gateway = 'tap';

  /// المفتاح العام للبوابة — يُستخدم لصفحات الدفع (آمن للنشر).
  static const String publishableKey = 'pk_test_XXXX';

  /// الرابط الأساسي لوظائف الدفع على Cloud Functions.
  /// مثال: https://us-central1-aevora-1f64f.cloudfunctions.net
  static const String functionsBaseUrl =
      'https://us-central1-aevora-1f64f.cloudfunctions.net';

  /// صفحة النجاح/الإلغاء بعد إتمام الدفع (روابط مؤقتة تُحدَّث عند النشر).
  static const String webAppBaseUrl = 'https://abowaaleed.github.io/aevora-backend/';

  /// هل الدفع مفعّل فعلاً؟ (يتطلب مفتاحاً عاماً حقيقياً + مفتاحاً سرياً على الخادم)
  static bool get paymentsEnabled =>
      publishableKey.isNotEmpty && !publishableKey.contains('XXXX');
}

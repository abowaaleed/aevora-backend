import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'client_auth.dart';
import 'client_plan.dart';
import 'payment_config.dart';

/// نتيجة طلب بدء عملية دفع.
class CheckoutResult {
  final bool started;
  final String? message;
  const CheckoutResult.started()
      : started = true,
        message = null;
  const CheckoutResult.failed(this.message) : started = false;
}

/// عميل الدفع: ينشئ جلسة دفع على خادم Cloud Functions (الذي يتكلم مع بوابة
/// Tap/Moyasar) ثم يفتح صفحة الدفع. عند نجاح الدفع يكتب الخادم خطة المستخدم
/// في Firestore ويقرأها [PlanStore] تلقائياً.
class PaymentClient {
  PaymentClient._();

  /// إنشاء جلسة دفع وفتح صفحة الدفع (في المتصفح على الويب، وفي المتصفح
  /// النظامي على الجوال ثم يعود المستخدم للتطبيق).
  static Future<CheckoutResult> startCheckout({
    required PlanTier tier,
  }) async {
    if (!PaymentConfig.paymentsEnabled) {
      return const CheckoutResult.failed(
          'الدفع الإلكتروني قيد التفعيل — تابعونا قريباً.');
    }
    try {
      final res = await http
          .post(
            Uri.parse('${PaymentConfig.functionsBaseUrl}/createCheckout'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'tier': tier.name,
              'gateway': PaymentConfig.gateway,
              'uid': currentUserId,
              if (currentEmail != null) 'email': currentEmail,
              'successUrl':
                  '${PaymentConfig.webAppBaseUrl}?checkout=success',
              'cancelUrl':
                  '${PaymentConfig.webAppBaseUrl}?checkout=cancelled',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        return CheckoutResult.failed(
            'تعذر بدء الدفع (${res.statusCode}) — أعد المحاولة.');
      }
      final url = (jsonDecode(res.body)['url'] ?? '').toString().trim();
      if (url.isEmpty) {
        return const CheckoutResult.failed(
            'لم تُجهَّز صفحة الدفع بعد — حاول لاحقاً.');
      }
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      return ok
          ? const CheckoutResult.started()
          : const CheckoutResult.failed('تعذر فتح صفحة الدفع.');
    } catch (e) {
      return CheckoutResult.failed('تعذر فتح صفحة الدفع: $e');
    }
  }

  /// دالة مستقبلية لإلغاء/إدارة الاشتراك عبر الخادم.
  static Future<CheckoutResult> cancelSubscription() async {
    if (!PaymentConfig.paymentsEnabled) {
      return const CheckoutResult.failed(
          'إدارة الاشتراك غير متاحة بعد — تواصل معنا.');
    }
    try {
      final res = await http
          .post(
            Uri.parse('${PaymentConfig.functionsBaseUrl}/cancelSubscription'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'uid': currentUserId}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        return const CheckoutResult.started();
      }
      return const CheckoutResult.failed(
          'تعذر إلغاء الاشتراك — تواصل معنا.');
    } catch (_) {
      return const CheckoutResult.failed('تعذر إلغاء الاشتراك — تواصل معنا.');
    }
  }
}

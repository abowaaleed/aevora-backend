import 'package:flutter/material.dart';

import '../client/client_auth.dart';
import '../client/client_payments.dart';
import '../client/client_plan.dart';
import '../client/payment_config.dart';

/// شاشة «الاشتراك والترقية»: بطاقات الخطط الثلاث (مجانية/مميز/مُدارة) مع
/// حالة الاشتراك الحالية وزر بدء الدفع عبر بوابة Tap/Moyasar.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _busy = false;

  Future<void> _subscribe(PlanTier tier) async {
    if (_busy) return;
    if (tier == PlanTier.free) return;
    final state = PlanStore.current.value;

    // الاشتراك المدفوع يتطلب حساباً لتوثيق الاشتراك ومزامنته.
    if (!isSignedIn) {
      final goLogin = await _confirm(
        title: 'تسجيل الدخول مطلوب',
        body: 'لتفعيل الاشتراك المدفوع وحمايته في حسابك، سجّل الدخول '
            'بحساب Google أولاً. بياناتك الحالية ستبقى محفوظة.',
        action: 'تسجيل الدخول',
      );
      if (goLogin == true && mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
            '/login', (_) => false);
      }
      return;
    }

    if (state.isPremium) {
      await _confirm(
        title: 'لديك اشتراك مفعّل',
        body: 'خطتك الحالية: ${state.label}. هل تريد التبديل إلى خطة أخرى؟ '
            'سيُلغى الاشتراك الحالي بعد انتهاء مدته.',
        action: 'التبديل',
      );
      // يكمل المستخدم بتجربة الخطة الجديدة.
    }

    setState(() => _busy = true);
    final result = await PaymentClient.startCheckout(tier: tier);
    setState(() => _busy = false);
    if (!mounted) return;

    if (!result.started) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message ?? '')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم فتح صفحة الدفع الآمنة — سيُفعَّل اشتراكك فور التأكيد.'),
      ),
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141A2A),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(body,
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.7)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(title: const Text('الاشتراك والترقية')),
      body: ValueListenableBuilder<PlanState>(
        valueListenable: PlanStore.current,
        builder: (context, state, _) {
          final freeDaily = PlanStore.freeProfessionalTtsCharsPerDay;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _statusCard(state),
              const SizedBox(height: 20),
              for (var i = 0; i < planCatalog.length; i++) ...[
                _planCard(planCatalog[i], state),
                if (i != planCatalog.length - 1) const SizedBox(height: 14),
              ],
              const SizedBox(height: 20),
              Card(
                color: const Color(0xFF141A2A),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('كيف يعمل الدفع؟',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const Text(
                        'تُنفَّذ المدفوعات عبر بوابة دفع مرخّصة (Tap/Moyasar) '
                        'وتدعم mada وApple Pay وSTC Pay. لا نطّلع أبداً على '
                        'بيانات بطاقتك — بعد تأكيد الدفع يُفعَّل اشتراكك '
                        'تلقائياً على كل أجهزتك. خطة «مميز» تستخدم مفتاحك، '
                        'وخطة «مُدارة» لا تحتاج أي مفاتيح.',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 13, height: 1.8),
                      ),
                      if (!PaymentConfig.paymentsEnabled) ...[
                        const SizedBox(height: 12),
                        const Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Color(0xFF81C784), size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'الدفع الإلكتروني قيد التفعيل وسيتوفر قريباً — '
                                'في الوقت الحالي يمكنك تجربة كل المزايا المجانية.',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'الحد المجاني اليومي للنطق الاحترافي: '
                        '$freeDaily حرف — ترتفع إلى اللانهاية مع «مميز/مُدارة».',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _statusCard(PlanState state) {
    final email = currentEmail;
    return Card(
      color: const Color(0xFF141A2A),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: state.isPremium
                    ? const Color(0xFF1D3A1D)
                    : const Color(0xFF16202E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                state.isPremium
                    ? Icons.workspace_premium_rounded
                    : Icons.auto_awesome_rounded,
                color: state.isPremium
                    ? const Color(0xFF81C784)
                    : Colors.white54,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.isPremium ? state.label : 'الخطة المجانية',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    !isSignedIn
                        ? 'غير مسجل الدخول — سجّل دخولك لتفعيل الاشتراك.'
                        : (email ?? '').isEmpty
                            ? 'متصلاً بحساب Google'
                            : email!,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (state.isPremium && state.endsAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'يجدد حتى ${_fmtDate(state.endsAt!)}',
                        style: const TextStyle(
                            color: Color(0xFF81C784), fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planCard(PlanInfo plan, PlanState state) {
    final isCurrent = state.isPremium && plan.tier == state.tier;
    final isCurrentFree = !state.isPremium && plan.tier == PlanTier.free;
    final selected = isCurrent || isCurrentFree;
    final accent = plan.recommended
        ? const Color(0xFF81C784)
        : Colors.white54;

    return Card(
      color: const Color(0xFF141A2A),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? const Color(0xFF81C784) : Colors.white12,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (plan.recommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D3A1D),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('الأكثر طلباً',
                        style: TextStyle(
                            color: Color(0xFF81C784), fontSize: 11)),
                  ),
                const Spacer(),
                Text(plan.title,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            Text(plan.price,
                style: TextStyle(
                    color: accent, fontSize: 22, fontWeight: FontWeight.w800)),
            Text(plan.subtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 12),
            for (final f in plan.features)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: Color(0xFF81C784), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(f,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: selected
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check),
                      label: Text(
                          isCurrentFree ? 'خطتك الحالية' : 'خطتك الحالية'),
                    )
                  : FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _subscribe(plan.tier),
                      icon: Icon(plan.tier == PlanTier.managed
                          ? Icons.shield_outlined
                          : Icons.workspace_premium_outlined),
                      label: Text(_busy
                          ? 'جارٍ التحويل للدفع...'
                          : 'اشترك الآن — ${plan.price}'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

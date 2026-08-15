import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'client_auth.dart';

/// مستويات الاشتراك في ايفورا:
/// - [free]: الخطة المجانية — تعمل بمفاتيح المستخدم وبحدود يومية.
/// - [premium]: مميز (بمفتاح المستخدم) — حدود أعلى/بلا حدود دون حاجة لخادم.
/// - [managed]: مُدارة — كل شيء مضمن عبر خادم آمن (بدون إدخال مفاتيح).
enum PlanTier { free, premium, managed }

/// حالة اشتراك المستخدم الحالية — محلية على الجهاز + مزامنة مع Firestore
/// عند تسجيل الدخول (تُكتب من بوابات الدفع عبر Cloud Functions).
class PlanState {
  final PlanTier tier;
  final bool active;
  final String provider;
  final DateTime? endsAt;

  const PlanState({
    this.tier = PlanTier.free,
    this.active = true,
    this.provider = 'local',
    this.endsAt,
  });

  bool get isPremium => active && tier != PlanTier.free;

  bool get isManaged => active && tier == PlanTier.managed;

  /// نص عربي مختصر لحالة الاشتراك (للواجهات).
  String get label {
    if (!active) return 'منتهي';
    switch (tier) {
      case PlanTier.free:
        return 'الخطة المجانية';
      case PlanTier.premium:
        return 'مميز';
      case PlanTier.managed:
        return 'مُدارة';
    }
  }

  Map<String, dynamic> toMap() => {
        'tier': tier.name,
        'active': active,
        'provider': provider,
        if (endsAt != null)
          'endsAt': endsAt!.millisecondsSinceEpoch,
      };

  static PlanState fromMap(Object? raw) {
    if (raw is! Map) return const PlanState();
    final tierName = (raw['tier'] ?? 'free').toString();
    final endsMs = (raw['endsAt'] as num?)?.toInt();
    return PlanState(
      tier: PlanTier.values.firstWhere(
        (t) => t.name == tierName,
        orElse: () => PlanTier.free,
      ),
      active: (raw['active'] as bool?) ?? true,
      provider: (raw['provider'] ?? 'local').toString(),
      endsAt: endsMs == null ? null : DateTime.fromMillisecondsSinceEpoch(endsMs),
    );
  }
}

/// مكتبة الخطط (للشاشات): السعر والميزات بالعربية.
class PlanInfo {
  final PlanTier tier;
  final String title;
  final String price;
  final String subtitle;
  final List<String> features;
  final bool recommended;

  const PlanInfo({
    required this.tier,
    required this.title,
    required this.price,
    required this.subtitle,
    required this.features,
    this.recommended = false,
  });
}

const List<PlanInfo> planCatalog = [
  PlanInfo(
    tier: PlanTier.free,
    title: 'مجانية',
    price: '0 ر.س',
    subtitle: 'إلى الأبد، بمفاتيحك',
    features: [
      'محادثة ومساعد شخصي بلا حدود',
      'النطق الاحترافي بحد يومي (3,000 حرف)',
      'رفع حتى 5 مستندات',
      'ملفات حتى 10 م.ب — ومساحة تخزين 50 م.ب',
      'المزامنة عند تسجيل الدخول',
    ],
  ),
  PlanInfo(
    tier: PlanTier.premium,
    title: 'مميز',
    price: '29 ر.س / شهر',
    subtitle: 'بمفتاحك الخاص',
    features: [
      'كل مزايا المجانية',
      'النطق الاحترافي بلا حدود',
      'رفع حتى 300 مستند',
      'ملفات حتى 50 م.ب — ومساحة تخزين 1 ج.ب',
      'تصدير المحادثات بدون ترويج',
      'أصوات إضافية وأولوية الدعم',
    ],
    recommended: true,
  ),
  PlanInfo(
    tier: PlanTier.managed,
    title: 'مُدارة',
    price: '49 ر.س / شهر',
    subtitle: 'بدون أي مفاتيح',
    features: [
      'كل مزايا «مميز»',
      'لا تحتاج مفاتيح Gemini/Groq',
      'استهلاك مُدار بلا انقطاع',
      'حماية المفتاح على خادم آمن',
    ],
  ),
];

/// حدود استهلاك المستندات لكل خطة — تُعرض في الواجهة وتُفرض عند الرفع.
class PlanQuota {
  final int maxFiles;
  final int maxFileSizeBytes;
  final int maxStorageBytes;

  const PlanQuota({
    required this.maxFiles,
    required this.maxFileSizeBytes,
    required this.maxStorageBytes,
  });

  bool get isUnlimited => maxFiles >= 100000;
}

/// خطة «مجانية»: عدد محدود من المستندات وحجم/مساحة معقولة للمتصفح والجوال.
const PlanQuota freePlanQuota = PlanQuota(
  maxFiles: 5,
  maxFileSizeBytes: 10 * 1024 * 1024, // 10 م.ب لكل ملف
  maxStorageBytes: 50 * 1024 * 1024, // 50 م.ب إجمالي
);

/// خطة «مميز/مُدارة»: مساحة واسعة تكفي للاستخدام اليومي بلا قلق.
const PlanQuota paidPlanQuota = PlanQuota(
  maxFiles: 300,
  maxFileSizeBytes: 50 * 1024 * 1024, // 50 م.ب لكل ملف
  maxStorageBytes: 1024 * 1024 * 1024, // 1 ج.ب إجمالي
);

/// حصة المستندات لخطة المستخدم الحالية.
PlanQuota quotaForPlan(PlanState state) =>
    state.isPremium ? paidPlanQuota : freePlanQuota;

/// إدارة حالة الاشتراك: قراءة من الجهاز (SharedPreferences) وربطها بحالة
/// الحساب في Firestore (المصدر الرسمي بعد الدفع عبر بوابة Tap/Moyasar).
class PlanStore {
  PlanStore._();

  static const _prefKey = 'aevora_plan';

  /// الحالة الحالية — اشترِك بها الشاشات عبر ValueListenableBuilder.
  static final ValueNotifier<PlanState> current =
      ValueNotifier<PlanState>(const PlanState());

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  static StreamSubscription<User?>? _authSub;
  static String? _uid;

  /// الحد المجاني اليومي للنطق الاحترافي (بالأحرف).
  static const int freeProfessionalTtsCharsPerDay = 3000;

  /// تحميل الاشتراك المحلي (يُستدعى عند بدء التطبيق).
  static Future<void> loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        current.value = PlanState.fromMap(jsonDecode(raw));
      }
    } catch (_) {}
  }

  static Future<void> _persistLocal(PlanState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(state.toMap()));
    } catch (_) {}
  }

  /// تطبيق حالة قادمة من السحابة (بعد الدفع أو عند سحب الحساب).
  static Future<void> applyRemote(Map<String, dynamic>? plan) async {
    if (plan == null) return;
    final state = PlanState.fromMap(plan);
    current.value = state;
    await _persistLocal(state);
  }

  /// ربط الاشتراك بحالة تسجيل الدخول ومستند المستخدم في Firestore.
  static void startListening() {
    if (!isAuthEnabled) return;
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      final uid = user?.uid;
      if (uid == _uid) return;
      _uid = uid;
      _docSub?.cancel();
      _docSub = null;
      if (user == null) return;
      _docSub = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen(
        (snap) {
          final plan = snap.data()?['plan'];
          if (plan is Map) {
            unawaited(applyRemote(Map<String, dynamic>.from(plan)));
          }
        },
        onError: (_) {},
      );
    });
  }
}

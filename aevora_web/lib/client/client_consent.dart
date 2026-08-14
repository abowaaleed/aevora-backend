import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'client_auth.dart';

/// عنصر موافقة (بيانات/اتصالات) يُعرض في شاشة «الموافقات والضوابط».
class ConsentItem {
  final String id;
  final String title;
  final String description;
  final bool required;
  const ConsentItem({
    required this.id,
    required this.title,
    required this.description,
    this.required = false,
  });
}

const List<ConsentItem> consentCatalog = [
  ConsentItem(
    id: 'processing',
    title: 'معالجة نصوصي وأوامري',
    description: 'إرسال نصوص المحادثات والأوامر إلى مزودي الذكاء الاصطناعي '
        '(Gemini/Groq) لمعالجتها وإنتاج الردود. لازمة لتشغيل الخدمة.',
    required: true,
  ),
  ConsentItem(
    id: 'audio',
    title: 'معالجة تسجيلاتي الصوتية',
    description: 'إرسال المقاطع الصوتية إلى خدمة التعرف على الصوت (Whisper) '
        'لتحويلها إلى نص.',
    required: true,
  ),
  ConsentItem(
    id: 'communication',
    title: 'تواصل الحساب والاشتراك',
    description: 'مراسلات إلكترونية متعلقة بالحساب والمزامنة والاشتراك '
        'وإشعارات الدفع (ليس تسويقاً).',
  ),
  ConsentItem(
    id: 'marketing',
    title: 'عروض وتحديثات تسويقية',
    description: 'رسائل اختيارية عن الميزات الجديدة والعروض. يمكنك إلغاؤها '
        'في أي وقت من هذه الشاشة.',
  ),
  ConsentItem(
    id: 'payment',
    title: 'بيانات الفواتير والاشتراك',
    description: 'تخزين تفاصيل الاشتراك والفواتير عبر بوابة الدفع عند '
        'الترقية إلى خطة مدفوعة.',
  ),
];

/// إدارة الموافقات: تُحفظ محلياً وتُزامن مع الحساب (اختياري عند الدخول).
class ConsentStore {
  ConsentStore._();

  static const _prefKey = 'aevora_consents';

  static final ValueNotifier<Map<String, bool>> current =
      ValueNotifier<Map<String, bool>>({});

  static Future<void> loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = <String, bool>{};
          for (final e in decoded.entries) {
            map[e.key.toString()] = e.value == true;
          }
          current.value = map;
        }
      }
    } catch (_) {}
  }

  static Future<void> _persistLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(current.value));
    } catch (_) {}
  }

  static Future<void> set(String id, bool value) async {
    final map = Map<String, bool>.from(current.value);
    map[id] = value;
    current.value = map;
    await _persistLocal();
    await _pushToCloud();
  }

  static Future<void> setMany(Map<String, bool> values) async {
    final map = Map<String, bool>.from(current.value)..addAll(values);
    current.value = map;
    await _persistLocal();
    await _pushToCloud();
  }

  static bool get(String id) => current.value[id] ?? false;

  static bool get hasAcceptedAllRequired =>
      consentCatalog.every((c) => !c.required || get(c.id));

  /// رفع الموافقات إلى مستند المستخدم عند تسجيل الدخول.
  static Future<void> _pushToCloud() async {
    if (!isAuthEnabled) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'consents': current.value}, SetOptions(merge: true));
    } catch (_) {}
  }

  /// سحب الموافقات القادمة من الحساب وتطبيقها محلياً.
  static Future<void> applyRemote(Object? consents) async {
    if (consents is! Map) return;
    final map = <String, bool>{};
    for (final e in consents.entries) {
      map[e.key.toString()] = e.value == true;
    }
    current.value = map;
    await _persistLocal();
  }
}

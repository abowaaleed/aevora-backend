import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'client_auth.dart';
import 'client_companion.dart';
import 'client_storage.dart';
import 'client_usage.dart';

/// مزامنة بيانات المستخدم (المحادثات، المساعد، العدادات) مع Cloud Firestore
/// بمفتاح حساب Google — لتبقى كل البيانات ملازمة للمستخدم في أي متصفح/هاتف.
///
/// النمط: Local-first — كل شيء يعمل محلياً أولاً (IndexedDB) ثم يُرفع
/// للسحابة بعد أي تعديل (debounce) ويُسحب عند تسجيل الدخول.
class SyncStore {
  SyncStore._();

  static const _collection = 'users';

  static Timer? _debounce;
  static User? _user;
  static StreamSubscription<User?>? _sub;
  static Completer<void>? _ready;

  static bool get _active => isAuthEnabled && _user != null;

  /// يُستدعى بعد [initFirebase]. يسحب بيانات الحساب عند الدخول ويربط التغيّرات.
  static void startListening() {
    if (!isAuthEnabled) return;
    _sub?.cancel();
    try {
      _sub = FirebaseAuth.instance.authStateChanges().listen((user) {
        _user = user;
        if (user != null) {
          _pullThenReady(user.uid);
        } else {
          _ready = null;
        }
      }, onError: (_) {
        // أي خطأ في تيار الجلسة لا يُسقط التطبيق.
        _user = null;
        _ready = null;
      });
    } catch (_) {
      _user = null;
      _ready = null;
    }
  }

  /// يُستدعى عند بدء التطبيق: إذا كانت هناك جلسة سابقة يُسحب البيانات قبل عرض
  /// الواجهة حتى لا تُفتح الشاشات ببيانات فارغة ثم تُحدَّث.
  static Future<void> prepare() async {
    if (!isAuthEnabled) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _user = user;
      _pullThenReady(user.uid);
    }
  }

  /// انتظار اكتمال أول سحب (تستدعيه شل قبل بناء الشاشات).
  static Future<void> waitForReady() async {
    final ready = _ready;
    if (ready == null) return;
    await ready.future.timeout(const Duration(seconds: 15), onTimeout: () {});
  }

  static void _pullThenReady(String uid) {
    _ready = Completer<void>();
    unawaited(_pullAndComplete(uid));
  }

  static Future<void> _pullAndComplete(String uid) async {
    await pullFor(uid);
    _ready?.complete();
  }

  /// سحب بيانات الحساب من Firestore وتطبيقها على IndexedDB المحلي.
  static Future<void> pullFor(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      final data = doc.data();
      if (data == null) return;
      await _applyToLocal(data);
    } catch (_) {
      // غياب الاتصال أو القواعد لا يعطّل التطبيق؛ يبقى يعمل محلياً.
    }
  }

  static Future<void> _applyToLocal(Map<String, dynamic> data) async {
    try {
      final chat = data['chat_messages'];
      if (chat is List && chat.isNotEmpty) {
        await LocalDb.kvPut('chat_messages', chat);
      }
      final comp = data['companion'];
      if (comp is Map && comp.isNotEmpty) {
        await LocalCompanion.importState(Map<String, dynamic>.from(comp));
      }
      final usage = data['usage_history'];
      if (usage is Map && usage.isNotEmpty) {
        await LocalUsage.mergeHistory(Map<String, dynamic>.from(usage));
      }
    } catch (_) {}
  }

  /// جدولة رفع بعد أي تعديل محلي (مع إلغاء الجدولة السابقة لتجميع الكتابات).
  static void schedulePush() {
    if (!_active) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 2000), () {
      unawaited(pushNow());
    });
  }

  /// رفع فوري للحالة الكاملة (يُستخدم عند تسجيل الخروج وقبل الإغلاق).
  static Future<void> pushNow() async {
    _debounce?.cancel();
    if (!_active) return;
    try {
      final state = await _collectLocalState();
      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_user!.uid)
          .set({
        ...state,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> _collectLocalState() async {
    return {
      'chat_messages': await LocalDb.kvGetValue('chat_messages') ?? [],
      'companion': await LocalCompanion.exportState(),
      'usage_history': await LocalUsage.history(),
    };
  }
}

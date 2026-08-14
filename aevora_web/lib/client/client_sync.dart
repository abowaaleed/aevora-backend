import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'client_auth.dart';
import 'client_companion.dart';
import 'client_rag.dart';
import 'client_storage.dart';
import 'client_usage.dart';
import 'web_lifecycle_stub.dart'
    if (dart.library.js_interop) 'web_lifecycle_web.dart' as web_lifecycle;

/// مزامنة بيانات المستخدم (المحادثات، المساعد، العدادات، المفاتيح، الملفات)
/// مع Cloud Firestore بمفتاح حساب Google — لتبقى كل البيانات ملازمة للمستخدم
/// في أي متصفح/هاتف.
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
  static bool _pushedAfterPull = false;
  // تتبّع آخر حالة جلسة لرفع/سحب فقط عند دخول أو خروج حقيقي، وليس عند
  // تجديد التوكن (يصدر حدثاً من نفس المستخدم) الذي قد يُسقط بيانات محلية
  // غير مرفوعة بعد.
  static String? _lastAuthUid;

  // حدود نقل الملفات عبر Firestore (مستند واحد ≤ 1MB).
  static const _maxSyncChunks = 400;
  static const _maxSyncDocChars = 450000;
  static const _maxBlobSyncBytes = 2 * 1024 * 1024;
  static const _segmentChars = 390000;
  static const _previewChars = 30000;

  /// يُستدعى بعد تطبيق حالة قادمة من السحابة (لإعادة تحميل المفاتيح في الواجهة).
  static void Function()? onStateApplied;

  /// يُزاد عند كل تطبيق لمحادثة قادمة من السحابة؛ تشترك شاشة المحادثة به
  /// لإعادة قراءة [messages] المحلية (فشل نظام الاشتراك في تحديث الواجهة).
  static final chatReloadTick = ValueNotifier<int>(0);

  /// يرفع المفاتيح إذا كانت هناك جلسة لكن المتصفح لم يعد في المقدمة — حماية
  /// من فقدان رسائل أثناء التبديل بين الأجهزة.
  static void flushIfSession() {
    if (!_active) return;
    unawaited(pushNow());
  }

  static bool get _active => isAuthEnabled && _user != null;

  /// يُستدعى بعد [initFirebase]. يسحب بيانات الحساب عند الدخول ويربط التغيّرات.
  static void startListening() {
    if (!isAuthEnabled) return;
    _sub?.cancel();
    try {
      _sub = FirebaseAuth.instance.authStateChanges().listen((user) {
        final uid = user?.uid;
        if (uid == _lastAuthUid) return;
        _lastAuthUid = uid;
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
      // عند مغادرة/إخفاء الصفحة (تحويل تبويب/إغلاق) نرفع أي مفتاح لم يُرفع بعد
      // حتى لا يضيع عند التبديل بين الأجهزة.
      // عند مغادرة/إخفاء الصفحة (تحويل تبويب/إغلاق) نرفع أي مفتاح لم يُرفع بعد
      // حتى لا يضيع عند التبديل بين الأجهزة.
      web_lifecycle.attachLifecycleFlush(flushIfSession);
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
      // منع سحب مزدوج: أول حدث من authStateChanges لنفس المستخدم يُتجاهل.
      _lastAuthUid = user.uid;
      _pullThenReady(user.uid);
    }
  }

  /// انتظار اكتمال أول سحب (تستدعيه شل قبل بناء الشاشات).
  static Future<void> waitForReady() async {
    final ready = _ready;
    if (ready == null) return;
    await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
  }

  static void _pullThenReady(String uid) {
    _pushedAfterPull = false;
    _ready = Completer<void>();
    unawaited(_pullAndComplete(uid));
  }

  static Future<void> _pullAndComplete(String uid) async {
    await pullFor(uid);
    _ready?.complete();
    // بعد أول سحب ارفع الحالة المحلية (مفاتيح/ملفات أُدخلت قبل الدخول أو أثناء
    // عدم الاتصال) حتى تتقارب الأجهزة معاً.
    if (!_pushedAfterPull) {
      _pushedAfterPull = true;
      await pushNow();
    }
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
      await _pullBlobs(uid, data);
    } catch (_) {
      // غياب الاتصال أو القواعد لا يعطّل التطبيق؛ يبقى يعمل محلياً.
    }
  }

  static Future<void> _applyToLocal(Map<String, dynamic> data) async {
    try {
      final chat = data['chat_messages'];
      if (chat is List) {
        await _mergeChatMessages(chat);
      }
      final comp = data['companion'];
      if (comp is Map && comp.isNotEmpty) {
        await LocalCompanion.importState(Map<String, dynamic>.from(comp));
      }
      final usage = data['usage_history'];
      if (usage is Map && usage.isNotEmpty) {
        await LocalUsage.mergeHistory(Map<String, dynamic>.from(usage));
      }
      final keys = data['keys'];
      if (keys is Map && keys.isNotEmpty) {
        await _applyCloudKeys(Map<String, dynamic>.from(keys));
      }
      await _applyCloudFiles(data);
    } catch (_) {}
    // أبلغ شاشة المحادثة أن المحادثة المحلية تغيّرت من السحابة حتى تعيد
    // قراءتها وتُحدّث رسائلها (نظام الاشتراك وحده لم يُحدث الواجهة).
    chatReloadTick.value++;
    try {
      onStateApplied?.call();
    } catch (_) {}
  }

  static Future<void> _mergeChatMessages(List<dynamic> cloud) async {
    try {
      final raw = await LocalDb.kvGetValue('chat_messages');
      await LocalDb.kvPut('chat_messages', mergeChatMessages(raw, cloud));
    } catch (_) {}
  }

  /// تطبيق مفاتيح قادمة من السحابة دون مسح مفاتيح محلية موجودة
  /// (الجهاز المحلي مصدر أولاً، والسحابة تملأ الفراغات).
  static Future<void> _applyCloudKeys(Map<String, dynamic> cloud) async {
    try {
      final local = await AppStorage.load();
      var gemini = local.geminiKey;
      var groq = local.groqKey;
      var email = local.email;
      var changed = false;
      if (gemini.trim().isEmpty) {
        final v = cloud['gemini']?.toString().trim() ?? '';
        if (v.isNotEmpty) {
          gemini = v;
          changed = true;
        }
      }
      if (groq.trim().isEmpty) {
        final v = cloud['groq']?.toString().trim() ?? '';
        if (v.isNotEmpty) {
          groq = v;
          changed = true;
        }
      }
      if (email.trim().isEmpty) {
        final v = cloud['email']?.toString().trim() ?? '';
        if (v.isNotEmpty) {
          email = v;
          changed = true;
        }
      }
      if (changed) {
        await AppStorage.save(geminiKey: gemini, groqKey: groq, email: email);
      }
    } catch (_) {}
  }

  /// تطبيق الملفات وشرائح البحث القادمة من السحابة للملفات غير الموجودة محلياً
  /// (الملفات المحلية تبقى هي المصدر وتُرفع هي نفسها).
  static Future<void> _applyCloudFiles(Map<String, dynamic> data) async {
    try {
      final local = await LocalDb.listFiles();
      final localNames = {
        for (final f in local) (f['name'] ?? f['id']).toString(),
      };

      final files = data['files'];
      if (files is List) {
        for (final f in files.whereType<Map>()) {
          final name = (f['name'] ?? f['id']).toString();
          if (name.isEmpty || localNames.contains(name)) continue;
          final preview = (f['textPreview'] ?? '').toString();
          await LocalDb.saveFileMeta({
            'id': name,
            'name': name,
            'size': (f['size'] as num?)?.toInt() ?? 0,
            'addedAt': (f['addedAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
            'text': preview,
            'status': (f['status'] ?? 'indexed').toString(),
          });
        }
      }

      final chunks = data['chunks'];
      if (chunks is List && chunks.isNotEmpty) {
        final byFile = <String, List<Map<String, dynamic>>>{};
        for (final c in chunks.whereType<Map>()) {
          final name = (c['file'] ?? '').toString();
          if (name.isEmpty || localNames.contains(name)) continue;
          byFile.putIfAbsent(name, () => []).add(Map<String, dynamic>.from(c));
        }
        for (final e in byFile.entries) {
          await LocalDb.clearChunksForFile(e.key);
          for (final c in e.value) {
            final text = (c['text'] ?? '').toString();
            if (text.trim().isEmpty) continue;
            final idx = (c['idx'] as num?)?.toInt() ?? 0;
            await LocalDb.saveChunk({
              'id': '${e.key}::$idx',
              'file': e.key,
              'idx': idx,
              'text': text,
              'vec': embedText(text),
            });
          }
        }
      }
    } catch (_) {}
  }

  /// سحب محتوى الملفات الخام (blobs) للملفات القادمة من السحابة وغير الموجودة
  /// محلياً، عبر تجزئة base64 مخزنة في مجموعة فرعية لكل حساب.
  static Future<void> _pullBlobs(
      String uid, Map<String, dynamic>? data) async {
    try {
      final files = data?['files'];
      if (files is! List || files.isEmpty) return;
      final local = await LocalDb.listFiles();
      final localNames = {
        for (final f in local) (f['name'] ?? f['id']).toString(),
      };
      final cloudDocs = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(uid)
          .collection('blobs')
          .get();
      for (final doc in cloudDocs.docs) {
        final name = doc.id;
        if (name.isEmpty || localNames.contains(name)) continue;
        final d = doc.data();
        final segs = d['segments'];
        if (segs is! Map) continue;
        final count = (d['count'] as num?)?.toInt() ?? segs.length;
        if (count <= 0) continue;
        final sb = StringBuffer();
        for (var i = 0; i < count; i++) {
          final s = segs['$i']?.toString() ?? '';
          if (s.isNotEmpty) sb.write(s);
        }
        if (sb.isEmpty) continue;
        final bytes = base64Decode(sb.toString());
        await LocalDb.saveFileBlob(name, Uint8ListBytes(bytes, name));
      }
    } catch (_) {}
  }

  /// جدولة رفع بعد أي تعديل محلي (مع إلغاء الجدولة السابقة لتجميع الكتابات).
  static void schedulePush() {
    if (!_active) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      unawaited(pushNow());
    });
  }

  /// رفع فوري للحالة الكاملة (يُستخدم عند تسجيل الخروج وقبل الإغلاق).
  static Future<void> pushNow() async {
    _debounce?.cancel();
    if (!_active) return;
    try {
      final state = await _collectLocalState();
      // دمج المحادثة مع ما هو موجود فعلاً في السحابة قبل الكتابة: أي رفع من
      // جهاز بقائمة أقدم/أقصر (تابع قديم، جهاز فارغ بعد مسح التخزين) لا
      // يمسح أبداً رسائل جهاز آخر — الدمج يضيف فقط ولا يحذف.
      try {
        final ref = FirebaseFirestore.instance
            .collection(_collection)
            .doc(_user!.uid);
        final cloud = await ref.get(const GetOptions(source: Source.server));
        final cloudChat = cloud.data()?['chat_messages'];
        if (cloudChat is List && cloudChat.isNotEmpty) {
          state['chat_messages'] =
              mergeChatMessages(state['chat_messages'], cloudChat);
        }
      } catch (_) {}
      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_user!.uid)
          .set({
        ...state,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
    await _pushBlobs(_user!.uid);
  }

  static Future<Map<String, dynamic>> _collectLocalState() async {
    final keys = await AppStorage.load();
    final files = <Map<String, dynamic>>[];
    try {
      final metaRows = await LocalDb.listFiles();
      for (final f in metaRows) {
        final text = (f['text'] ?? '').toString();
        files.add({
          'id': f['id']?.toString() ?? '',
          'name': f['name']?.toString() ?? '',
          'size': (f['size'] as num?)?.toInt() ?? 0,
          'addedAt': (f['addedAt'] as num?)?.toInt() ?? 0,
          'status': f['status']?.toString() ?? 'indexed',
          'textPreview': text.length > _previewChars
              ? text.substring(0, _previewChars)
              : text,
        });
      }
    } catch (_) {}
    var chunks = <Map<String, dynamic>>[];
    try {
      final rows = await LocalDb.allChunks();
      chunks = [
        for (final c in rows.take(_maxSyncChunks))
          {
            'file': c['file']?.toString() ?? '',
            'idx': (c['idx'] as num?)?.toInt() ?? 0,
            'text': c['text']?.toString() ?? '',
          }
      ];
      // خفض عدد الشرائح إن اقترب الحجم من حد مستند Firestore (1MB).
      while (chunks.length > 100 && jsonEncode(chunks).length > _maxSyncDocChars) {
        chunks = chunks.sublist(0, chunks.length ~/ 2);
      }
    } catch (_) {}
    return {
      'chat_messages': await LocalDb.kvGetValue('chat_messages') ?? [],
      'companion': await LocalCompanion.exportState(),
      'usage_history': await LocalUsage.history(),
      'keys': keys.toCloudMap(),
      'files': files,
      'chunks': chunks,
    };
  }

  /// رفع محتوى الملفات (blobs) عبر تجزئة base64 في مجموعة فرعية، مع تخطّي
  /// الملفات الكبيرة (أكبر من حد مزامنة الملفات) والملفات غير المتغيّرة
  /// (بمقارنة بصمة FNV) حتى لا تُرفع من جديد مع كل تعديل بسيط.
  static Future<void> _pushBlobs(String uid) async {
    try {
      final files = await LocalDb.listFiles();
      final localNames = <String>{};
      const hashKey = 'synced_blob_hashes';
      final raw = await LocalDb.kvGetValue(hashKey);
      final hashes =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      for (final f in files) {
        final name = (f['name'] ?? f['id']).toString();
        if (name.isEmpty) continue;
        localNames.add(name);
        final size = (f['size'] as num?)?.toInt() ?? 0;
        if (size <= 0 || size > _maxBlobSyncBytes) continue;
        final blob = await LocalDb.fileBlob(name);
        if (blob == null) continue;
        final hash = _hashBytes(blob.bytes);
        if (hashes[name] == hash) continue;
        await _uploadBlob(uid, name, blob.bytes);
        hashes[name] = hash;
      }
      await LocalDb.kvPut(hashKey, hashes);
      // حذف أرشيف السحابة لأي ملف لم يعد موجوداً محلياً.
      final existing = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(uid)
          .collection('blobs')
          .get();
      for (final doc in existing.docs) {
        if (!localNames.contains(doc.id)) {
          await doc.reference.delete();
        }
      }
    } catch (_) {}
  }

  static Future<void> _uploadBlob(
      String uid, String name, List<int> bytes) async {
    final b64 = base64Encode(bytes);
    final segments = <String, String>{};
    var idx = 0;
    var n = 0;
    while (idx < b64.length) {
      final end = (idx + _segmentChars) < b64.length
          ? idx + _segmentChars
          : b64.length;
      segments['$n'] = b64.substring(idx, end);
      idx = end;
      n++;
    }
    await FirebaseFirestore.instance
        .collection(_collection)
        .doc(uid)
        .collection('blobs')
        .doc(name)
        .set({
      'segments': segments,
      'count': n,
      'size': bytes.length,
      'filename': name,
    }, SetOptions(merge: true));
  }

  /// بصمة سريعة ومحددة لمحتوى الملف (لتجنب إعادة الرفع عند كل تعديل بسيط).
  /// قيمها ضمن نطاق الأعداد الدقيقة في JavaScript (أقل من 2^53).
  static String _hashBytes(List<int> bytes) {
    var h1 = 5381;
    var h2 = 0x1F123BB5;
    for (final b in bytes) {
      h1 = (h1 * 33) ^ b;
      h2 = (h2 * 131) + b;
      h1 &= 0xFFFFFFFF;
      h2 &= 0xFFFFFFFF;
    }
    return '${h1.toRadixString(16)}${h2.toRadixString(16)}';
  }
}

/// دمج رسائل المحادثة القادمة من السحابة مع المحلية بدل استبدالها.
///
/// السبب: السحب (عند فتح التطبيق أو الدخول) قد يجلب نسخة أقدم من المحادثة
/// من Firestore، فإذا استُبدل المحلي بها تُمسح رسالة كُتبت للتو ولم تُرفع
/// بعد — خصوصاً عند فتح نفس الحساب على عدة أجهزة. الدمج يحفظ الرسائل
/// المحلية الأحدث ويملأ الفراغات من السحابة فقط.
List<Map<String, dynamic>> mergeChatMessages(
    Object? localRaw, List<dynamic> cloud) {
  final merged = <Map<String, dynamic>>[];
  final seen = <String>{};

  void add(Map<String, dynamic> m) {
    final text = (m['text'] ?? '').toString();
    if (text.trim().isEmpty) return;
    final id = (m['id'] ?? '').toString().trim();
    final role = (m['role'] ?? '').toString();
    final key = id.isNotEmpty ? 'id:$id' : 'pair:$role|${m['text']}';
    if (!seen.add(key)) return;
    merged.add({
      'id': id.isNotEmpty ? id : '${DateTime.now().microsecondsSinceEpoch}',
      'role': role.isEmpty ? 'model' : role,
      'text': text,
    });
  }

  // المحلية أولاً (الجهاز الحالي هو المصدر الأحدث)، ثم رسائل السحابة
  // غير الموجودة محلياً تُضاف كاملة — فلا تُمسح أي رسالة من أي جهاز.
  for (final m in (localRaw is List ? localRaw : const []).whereType<Map>()) {
    add(Map<String, dynamic>.from(m));
  }
  for (final m in cloud.whereType<Map>()) {
    add(Map<String, dynamic>.from(m));
  }

  if (merged.length > 100) {
    merged.removeRange(0, merged.length - 100);
  }
  return merged;
}

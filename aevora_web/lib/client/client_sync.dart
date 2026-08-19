import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'client_auth.dart';
import 'client_companion.dart';
import 'client_consent.dart';
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
  static Timer? _retryTimer;
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
  static const _maxBlobSyncBytes = 50 * 1024 * 1024;
  static const _previewChars = 30000;
  // كل جزء من الملف الكبير يُخزن في مستند مستقل ≤ _partChars حرف base64
  // (≈ 300KB) ليبقى مستند Firestore الواحد بعيداً عن حد 1MB.
  static const _partChars = 300000;
  // شواهد القبور (tombstones): أسماء الملفات التي حذفها المستخدم محلياً ولم
  // تصل حذوفاتها للسحابة بعد — تمنع السحب من إحياء ملف مُحذوف على هذا الجهاز.
  static const _deletedKey = 'deleted_files';

  /// مفاتيح شواهد القبور **السحابية** داخل مستند المستخدم (خريطة اسم→وقت):
  /// تُكتب فور الحذف بكتابة صغيرة مستقلة حتى يعرفها كل جهاز (حتى الجديد
  /// أول مرة) حتى لو فشلت دفعة الحالة الكاملة، وتُحذف بعد نجاح رفع كامل
  /// يطابق السحابة بالمحلي.
  static const _deletedCloudKey = 'deletedFiles';

  /// هل رصدنا حذوفات سحابية معلّقة (تُعاد المحاولة تلقائياً حتى تُنظَّف).
  static bool _cloudTombstonesPending = false;

  /// مستمع التغييرات اللحظي على مستند المستخدم — يُطبّق أي تغيير قادم من
  /// الأجهزة الأخرى فور حدوثه (سحب/حذف/رسائل...) دون انتظار إعادة الدخول.
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _cloudSub;

  /// حماية من الاسترجاع: أثناء رفع محلي (كتابة مستند المستخدم) نتجاهل ما
  /// يرتد إلينا من المستمع حتى لا نطبّق بياناتنا نحن ونُعيد سحب الملفات.
  static bool _pushingNow = false;

  static Future<Set<String>> _deletedNames() async {
    final v = await LocalDb.kvGetValue(_deletedKey);
    if (v is List) return v.map((e) => e.toString()).toSet();
    return <String>{};
  }

  static Future<void> _addDeletedName(String name) async {
    final set = await _deletedNames();
    set.add(name);
    await LocalDb.kvPut(_deletedKey, set.toList());
  }

  static Future<void> _clearDeletedNames() async {
    await LocalDb.kvDelete(_deletedKey);
  }

  /// أسماء الملفات المحذوفة في السحابة نفسها (خريطة `deletedFiles` في مستند
  /// المستخدم) — يعرفها أي جهاز يسحبها، بخلاف شواهد القبور المحلية.
  static Set<String> _cloudDeletedNames(Map<String, dynamic> data) {
    final raw = data[_deletedCloudKey];
    if (raw is Map) return raw.keys.map((e) => e.toString()).toSet();
    return <String>{};
  }

  /// يُستدعى بعد تطبيق حالة قادمة من السحابة (لإعادة تحميل المفاتيح في الواجهة).
  static void Function()? onStateApplied;

  /// يُزاد عند كل تطبيق لمحادثة قادمة من السحابة؛ تشترك شاشة المحادثة به
  /// لإعادة قراءة [messages] المحلية (فشل نظام الاشتراك في تحديث الواجهة).
  static final chatReloadTick = ValueNotifier<int>(0);

  /// يُزاد عند كل تطبيق لأي بيانات قادمة من السحابة (عدادات/ملفات/مفاتيح...)
  /// بعد إنشاء الشاشات؛ تشترك به شاشات «المستندات» و«الإعدادات» لإعادة
  /// التحميل — لضمان ظهور العدادات والملفات تلقائياً دون حاجة لتحديث يدوي
  /// حتى لو اكتمل السحب الأول بعد بناء الواجهة.
  static final cloudAppliedTick = ValueNotifier<int>(0);

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
          _attachCloudListener(user.uid);
          _pullThenReady(user.uid);
        } else {
          _cloudSub?.cancel();
          _cloudSub = null;
          _ready = null;
        }
      }, onError: (_) {
        // أي خطأ في تيار الجلسة لا يُسقط التطبيق.
        _user = null;
        _ready = null;
      });
      // عند مغادرة/إخفاء الصفحة (تحويل تبويب/إغلاق) نرفع أي مفتاح لم يُرفع بعد
      // حتى لا يضيع عند التبديل بين الأجهزة.
      web_lifecycle.attachLifecycleFlush(flushIfSession);
      // إعادة محاولة تلقائية لمزامنة الحذوفات المعلّقة حتى مع الانقطاعات.
      startDeleteRetryTimer();
    } catch (_) {
      _user = null;
      _ready = null;
    }
  }

  /// مؤقّت دوري يعيد محاولة رفع الحذوفات المعلّقة (محلية أو سحابية) حتى
  /// تُنظَّف من السحابة دون تدخل المستخدم. التكلفة: لا يقرأ السحابة إلا
  /// عندما يكون هناك حذف معلّق فعلاً.
  static void startDeleteRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_retryPendingSync());
    });
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
      _attachCloudListener(user.uid);
      _pullThenReady(user.uid);
    }
  }

  /// ربط مستمع التغييرات اللحظي بمستند `users/{uid}`: أي تعديل قادم من جهاز
  /// آخر (رفع ملف، حذف، رسالة...) يُطبَّق محلياً فوراً ويرفع الواجهة، دون
  /// الحاجة لإعادة الدخول أو الضغط على «تحديث». يُلغى القديم عند تبديل الحساب.
  static void _attachCloudListener(String uid) {
    _cloudSub?.cancel();
    try {
      _cloudSub = FirebaseFirestore.instance
          .collection(_collection)
          .doc(uid)
          .snapshots()
          .listen(
        (snap) => unawaited(_onCloudSnapshot(uid, snap)),
        onError: (_) {},
      );
    } catch (_) {}
  }

  /// تطبيق تغيير لحظي وارد من مستند المستخدم على المحلي، ثم سحب أي ملفات
  /// جديدة غير موجودة محلياً (بما فيها ملفات رُفعت من جهاز آخر).
  static Future<void> _onCloudSnapshot(
      String uid, DocumentSnapshot<Map<String, dynamic>> snap) async {
    try {
      // نتجاهل الأصداء الناتجة عن رفعنا المحلي (كتابة معلّقة أو قيد التنفيذ)
      // فلا نطبّق بياناتنا نحن مرتين ولا نُحدث الواجهة عبثاً.
      if (_pushingNow || snap.metadata.hasPendingWrites) return;
      final data = snap.data();
      if (data == null) return;
      await _applyToLocal(data);
      await _pullBlobs(uid, data);
    } catch (_) {}
  }

  /// سحب فوري للحالة الكاملة من السحابة وتطبيقها محلياً — يستدعيه زر
  /// «تحديث» في شاشة المستندات، فلا يبقى التحديث معتمداً على مستمع
  /// التغييرات اللحظي وحده.
  static Future<void> pullNow() async {
    if (!_active) return;
    await pullFor(_user!.uid);
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
      final consents = data['consents'];
      if (consents is Map) {
        await ConsentStore.applyRemote(consents);
      }
      await _applyCloudFiles(data);
      final reminders = data['reminders'];
      if (reminders is Map && reminders.isNotEmpty) {
        await LocalDb.kvPut(
            'aevora_reminder_prefs_v2', Map<String, dynamic>.from(reminders));
      }
    } catch (_) {}
    // أبلغ شاشة المحادثة أن المحادثة المحلية تغيّرت من السحابة حتى تعيد
    // قراءتها وتُحدّث رسائلها (نظام الاشتراك وحده لم يُحدّث الواجهة).
    chatReloadTick.value++;
    cloudAppliedTick.value++;
    // إن رصدنا حذوفات سحابية معلّقة (حذف من جهاز آخر لم يُنظَّف بعد) نُحرّك
    // رفعاً يُنظّفها من السحابة على هذا الجهاز أيضاً.
    if (_cloudDeletedNames(data).isNotEmpty) {
      _cloudTombstonesPending = true;
      schedulePush();
    }
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
  /// (الملفات المحلية تبقى هي المصدر وتُرفع هي نفسها). لا يعيد أبداً ملفاً
  /// حذفه المستخدم محلياً مؤخراً (شاهد قبر) حتى لو بقي في السحابة لحين
  /// اكتمال مزامنة الحذف.
  static Future<void> _applyCloudFiles(Map<String, dynamic> data) async {
    try {
      final local = await LocalDb.listFiles();
      final localNames = {
        for (final f in local) (f['name'] ?? f['id']).toString(),
      };
      final deleted = await _deletedNames();
      deleted.addAll(_cloudDeletedNames(data));

      final files = data['files'];
      if (files is List) {
        for (final f in files.whereType<Map>()) {
          final name = (f['name'] ?? f['id']).toString();
          if (name.isEmpty ||
              deleted.contains(name) ||
              localNames.contains(name)) {
            continue;
          }
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
          if (name.isEmpty ||
              deleted.contains(name) ||
              localNames.contains(name)) {
            continue;
          }
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
  /// محلياً، عبر تجزئة base64 مخزنة في مجموعة فرعية لكل حساب — مع دعم
  /// الملفات الكبيرة المقسّمة على عدة مستندات (multi). يستدعيه السحب الأول
  /// ومستمع التغييرات اللحظي، لذا يُخرج مبكراً إن لم يظهر ملف جديد.
  static Future<void> _pullBlobs(
      String uid, Map<String, dynamic>? data) async {
    try {
      final files = data?['files'];
      if (files is! List || files.isEmpty) return;
      final wanted = <String>{};
      final deleted = await _deletedNames();
      if (data != null) deleted.addAll(_cloudDeletedNames(data));
      for (final f in files.whereType<Map>()) {
        final name = (f['name'] ?? f['id']).toString();
        if (name.isEmpty || deleted.contains(name)) continue;
        final blob = await LocalDb.fileBlob(name);
        if (blob == null || blob.bytes.isEmpty) wanted.add(name);
      }
      if (wanted.isEmpty) return;
      final cloudDocs = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(uid)
          .collection('blobs')
          .get();
      final docsById = {for (final d in cloudDocs.docs) d.id: d};
      for (final doc in cloudDocs.docs) {
        final name = doc.id;
        if (!wanted.contains(name)) continue;
        final d = doc.data();
        final isMulti = d['multi'] == true;
        if (isMulti) {
          final count = (d['count'] as num?)?.toInt() ?? 0;
          if (count <= 0) continue;
          final sb = StringBuffer();
          var ok = true;
          for (var i = 0; i < count; i++) {
            final s = docsById['$name#$i']?.data()['s']?.toString() ?? '';
            if (s.isEmpty) {
              ok = false;
              break;
            }
            sb.write(s);
          }
          if (!ok || sb.isEmpty) continue;
          final bytes = base64Decode(sb.toString());
          await LocalDb.saveFileBlob(name, Uint8ListBytes(bytes, name));
        } else {
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
  /// يرجع true إن حُدِّثت السحابة فعلاً (للمزامنات الحرجة كالحذف).
  static Future<bool> pushNow() async {
    _debounce?.cancel();
    if (!_active) return false;
    _pushingNow = true;
    var pushed = false;
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
        final deleted = await _deletedNames();
        deleted.addAll(_cloudDeletedNames(cloud.data() ?? const {}));
        state['files'] = mergeFileLists(
          state['files'],
          cloud.data()?['files'],
          deleted,
        );
        state['chunks'] = mergeChunkLists(
          state['chunks'],
          cloud.data()?['chunks'],
          deleted,
        );
      } catch (_) {}
      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_user!.uid)
          .set({
        ...state,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      pushed = true;
      await _pushBlobs(_user!.uid);
      // بعد نجاح رفع الحالة الكاملة أصبحت السحابة مطابقة للمحلي، فلم يعد هناك
      // أي ملف محذوف متبقٍ في السحابة — نمسح شواهد القبور (المحلية والسحابية)
      // حتى لا تُحجب ملفات أُعيد رفعها لاحقاً بنفس الاسم.
      if (pushed) {
        await _clearDeletedNames();
        _cloudTombstonesPending = false;
        await _pruneCloudTombstones();
      }
    } catch (_) {}
    _pushingNow = false;
    return pushed;
  }

  /// حذف ملف نهائياً من الجهاز ثم مزامنة الحذف فوراً مع كل الأجهزة.
  /// يكتب أولاً شاهد قبر في السحابة (كتابة صغيرة مستقلة) حتى تعرف كل الأجهزة
  /// بالحذف حتى لو فشلت دفعة الحالة الكاملة، ثم يدفع الحالة كاملة.
  /// يرجع true إن اكتملت أي مزامنة فعلية للحذف على السحابة.
  static Future<bool> deleteFileEverywhere(String filename) async {
    await LocalDb.deleteFile(filename);
    await LocalDb.clearChunksForFile(filename);
    await _addDeletedName(filename);
    final cloudTombstoneOk = await _writeCloudTombstones([filename]);
    final ok = await pushNow();
    // لو فشل الرفع تُبقى شواهد القبر (محلياً وسحابياً) لتمنع السحب من إحياء
    // الملف في أي جهاز، وتُحذف تلقائياً بعد نجاح أي رفع لاحق.
    return ok || cloudTombstoneOk;
  }

  /// حذف مجموعة ملفات نهائياً من الجهاز ثم مزامنة الحذف مع كل الأجهزة بدفعة
  /// واحدة (شواهد قبور سحابية + رفع كامل) — أسرع وأخف من الحذف ملفاً ملفاً.
  static Future<bool> deleteAllEverywhere(List<String> filenames) async {
    for (final n in filenames) {
      await LocalDb.deleteFile(n);
      await LocalDb.clearChunksForFile(n);
      await _addDeletedName(n);
    }
    final cloudTombstoneOk = await _writeCloudTombstones(filenames);
    final ok = await pushNow();
    return ok || cloudTombstoneOk;
  }

  /// كتابة صغيرة مستقلة لشواهد قبور في السحابة (خريطة اسم→وقت داخل مستند
  /// المستخدم) — تنجح حتى لو فشلت دفعة الحالة الكاملة بعدها.
  static Future<bool> _writeCloudTombstones(List<String> names) async {
    if (!_active || names.isEmpty) return false;
    _pushingNow = true;
    try {
      final tombstones = <String, Object>{
        for (final n in names) n: DateTime.now().millisecondsSinceEpoch,
      };
      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_user!.uid)
          .set({_deletedCloudKey: tombstones}, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    } finally {
      _pushingNow = false;
    }
  }

  /// حذف شواهد القبور السحابية بعد تأكيد أن السحابة لم تعد تحوي الملفات
  /// المحذوفة (بعد رفع كامل ناجح يجعل `files` مطابقاً للمحلي).
  static Future<void> _pruneCloudTombstones() async {
    if (!_active) return;
    _pushingNow = true;
    try {
      final ref = FirebaseFirestore.instance
          .collection(_collection)
          .doc(_user!.uid);
      final cloud = await ref.get(const GetOptions(source: Source.server));
      final data = cloud.data();
      if (data == null) return;
      final names = _cloudDeletedNames(data);
      if (names.isEmpty) return;
      final updates = <String, Object>{};
      for (final n in names) {
        updates['$_deletedCloudKey.$n'] = FieldValue.delete();
      }
      await ref.update(updates);
    } catch (_) {}
    finally {
      _pushingNow = false;
    }
  }

  /// إعادة محاولة تلقائية لمزامنة الحذف كل فترة قصيرة ما دامت هناك حذوفات
  /// معلّقة (محلية أو سحابية) — حتى تلتقي السحابة مع الأجهزة بعد أي انقطاع
  /// دون تدخل المستخدم، ولا تُعاد الملفات المحذوفة على أي جهاز.
  static Future<void> _retryPendingSync() async {
    if (!_active) return;
    try {
      final local = await _deletedNames();
      if (local.isEmpty && !_cloudTombstonesPending) return;
      final ok = await pushNow();
      if (ok) _cloudTombstonesPending = false;
    } catch (_) {}
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
      'reminders': await LocalDb.kvGetValue('aevora_reminder_prefs_v2') ?? {},
    };
  }

  /// رفع محتوى الملفات (blobs) عبر تجزئة base64 في مجموعة فرعية، مع دعم
  /// الملفات الكبيرة بتقسيمها على عدة مستندات (multi) لتجاوز حد مستند
  /// Firestore (~1 م.ب) — والتخطّي فقط لما يتجاوز حد المزامنة الأعلى
  /// (50 م.ب) أو غير المتغيّر (بمقارنة بصمة FNV) حتى لا يُرفع من جديد.
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
      final deleted = await _deletedNames();
      if (deleted.isEmpty) return;
      final existing = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(uid)
          .collection('blobs')
          .get();
      for (final doc in existing.docs) {
        final baseName = doc.id.split('#').first;
        if (deleted.contains(baseName)) {
          await doc.reference.delete();
        }
      }
    } catch (_) {}
  }

  static Future<void> _uploadBlob(
      String uid, String name, List<int> bytes) async {
    final b64 = base64Encode(bytes);
    final ref = FirebaseFirestore.instance
        .collection(_collection)
        .doc(uid)
        .collection('blobs');
    // حذف أي أرشيف سابق لنفس الملف (دليل أو أجزاء) قبل إعادة الكتابة.
    try {
      final prev = await ref.get();
      for (final doc in prev.docs) {
        if (doc.id == name || doc.id.startsWith('$name#')) {
          await doc.reference.delete();
        }
      }
    } catch (_) {}

    if (b64.length <= _partChars) {
      // ملف صغير: مستند واحد بالصيغة القديمة (متوافق مع الأجهزة السابقة).
      await ref.doc(name).set({
        'segments': {'0': b64},
        'count': 1,
        'size': bytes.length,
        'filename': name,
      }, SetOptions(merge: true));
      return;
    }

    // ملف كبير: وثيقة دليل + أجزاء في مستندات مستقلة، لأن مستند Firestore
    // الواحد محدود بحوالي 1 م.ب — وهذا ما كان يُسقط رفع الملفات الكبيرة.
    var n = 0;
    var idx = 0;
    while (idx < b64.length) {
      final end = (idx + _partChars) < b64.length ? idx + _partChars : b64.length;
      await ref.doc('$name#$n').set({
        'file': name,
        'part': n,
        's': b64.substring(idx, end),
      });
      idx = end;
      n++;
    }
    await ref.doc(name).set({
      'multi': true,
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

/// اتحاد قوائم الملفات حسب الاسم: المحلي يغلب إن وُجد، والسحابة تملأ النقص.
/// جهاز جديد فارغ لا يمسح ملفات الحساب.
List<Map<String, dynamic>> mergeFileLists(
  Object? localRaw,
  Object? cloudRaw,
  Set<String> deleted,
) {
  final byName = <String, Map<String, dynamic>>{};
  void add(Object? raw, {required bool overwrite}) {
    if (raw is! List) return;
    for (final f in raw.whereType<Map>()) {
      final name = (f['name'] ?? f['id']).toString();
      if (name.isEmpty || deleted.contains(name)) continue;
      if (!overwrite && byName.containsKey(name)) continue;
      byName[name] = Map<String, dynamic>.from(f);
    }
  }

  add(cloudRaw, overwrite: false);
  add(localRaw, overwrite: true);
  return byName.values.toList();
}

List<Map<String, dynamic>> mergeChunkLists(
  Object? localRaw,
  Object? cloudRaw,
  Set<String> deleted,
) {
  final byId = <String, Map<String, dynamic>>{};
  void add(Object? raw, {required bool overwrite}) {
    if (raw is! List) return;
    for (final c in raw.whereType<Map>()) {
      final file = (c['file'] ?? '').toString();
      if (file.isEmpty || deleted.contains(file)) continue;
      final idx = (c['idx'] as num?)?.toInt() ?? 0;
      final id = '$file::$idx';
      if (!overwrite && byId.containsKey(id)) continue;
      byId[id] = Map<String, dynamic>.from(c);
    }
  }

  add(cloudRaw, overwrite: false);
  add(localRaw, overwrite: true);
  return byId.values.toList();
}

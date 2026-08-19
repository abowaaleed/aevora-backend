import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

// ──────────────────────────────────────────────
//  نموذج البيانات: عنصر تنبيه واحد
// ──────────────────────────────────────────────

enum ReminderType { idea, task }

class ReminderItem {
  final String id;
  final ReminderType type;
  final String title;
  final bool enabled;
  final int hour;
  final int minute;
  final List<int> days;
  final String interests;

  const ReminderItem({
    required this.id,
    required this.type,
    this.title = '',
    this.enabled = true,
    this.hour = 9,
    this.minute = 0,
    this.days = const [0, 1, 2, 3, 4, 5, 6],
    this.interests = '',
  });

  bool get everyDay => days.length == 7;

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get daysLabel {
    if (everyDay) return 'كل يوم';
    if (days.isEmpty) return 'بدون أيام';
    const names = ['سبت', 'أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة'];
    return days.map((d) => names[d]).join(' · ');
  }

  ReminderItem copyWith({
    String? id,
    ReminderType? type,
    String? title,
    bool? enabled,
    int? hour,
    int? minute,
    List<int>? days,
    String? interests,
  }) =>
      ReminderItem(
        id: id ?? this.id,
        type: type ?? this.type,
        title: title ?? this.title,
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        days: days ?? this.days,
        interests: interests ?? this.interests,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'days': days,
        'interests': interests,
      };

  factory ReminderItem.fromJson(Map<String, dynamic> j) => ReminderItem(
        id: j['id'] as String? ?? '',
        type: ReminderType.values.firstWhere(
          (e) => e.name == j['type'],
          orElse: () => ReminderType.idea,
        ),
        title: j['title'] as String? ?? '',
        enabled: j['enabled'] != false,
        hour: (j['hour'] as num?)?.toInt() ?? 9,
        minute: (j['minute'] as num?)?.toInt() ?? 0,
        days: (j['days'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [0, 1, 2, 3, 4, 5, 6],
        interests: j['interests'] as String? ?? '',
      );

  static String generateId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}

// ──────────────────────────────────────────────
//  تفضيلات التنبيهات (قائمة عناصر)
// ──────────────────────────────────────────────

class ReminderPrefs {
  final List<ReminderItem> items;

  const ReminderPrefs({this.items = const []});

  ReminderPrefs copyWith({List<ReminderItem>? items}) =>
      ReminderPrefs(items: items ?? this.items);

  List<ReminderItem> get ideas =>
      items.where((r) => r.type == ReminderType.idea).toList();

  List<ReminderItem> get tasks =>
      items.where((r) => r.type == ReminderType.task).toList();

  Map<String, dynamic> toJson() => {
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory ReminderPrefs.fromJson(Map<String, dynamic> j) => ReminderPrefs(
        items: (j['items'] as List<dynamic>?)
                ?.map((e) =>
                    ReminderItem.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            [],
      );
}

// ──────────────────────────────────────────────
//  محتوى يومي: أفكار وسلوكيات ونصائح
// ──────────────────────────────────────────────

class DailyContent {
  DailyContent._();

  static const _ideas = [
    'اللغة الإنجليزية بيئة غنية: اجعل هاتفك بالإنجليزية لتعلّم أسرع.',
    'اقرأ فقرة إنجليزية واحدة يومياً حتى لو كانت قصيرة.',
    'تعلّم كلمة جديدة وضعها في جملة — التكرار هو المفتاح.',
    'شاهد فيديو بالإنجليزية بدون ترجمة لمدة 5 دقائق.',
    'فكر بلغة الإنجليزية: حاول تسمية الأشياء من حولك.',
    'اسمع بودكاستاً إنجليزياً أثناء التنقل.',
    'اكتب يومياتك بالإنجليزية — حتى جملة واحدة.',
    'تحدّث مع نفسك بالإنجليزية أمام المرآة.',
    'تعلّم تعابير يومية شائعة واستخدمها اليوم.',
    'استمع لأغنية إنجليزية واحفظ كلماتها.',
    'اقرأ قصة قصيرة بالإنجليزية و-summaryها بالعربي.',
    'تعلّم التحيات والتعارف بشكل رسمي و informal.',
    'غيّر لغة تطبيقاتك إلى الإنجليزية.',
    'شاهد حلقة من مسلسل إنجليزي مع ترجمة إنجليزية.',
    'تدرب على النطق: اقرأ بصوت عالٍ لمدة 3 دقائق.',
    'اكتب 5 جمل جديدة عن يومك اليوم بالإنجليزية.',
    'تعلّم الفروق بين since و for و during.',
    'جرّب التفكير بالإنجليزية قبل النوم.',
    'اقرأ مقالاً قصيراً من BBC Learning English.',
    'تعلّم 3 أفعال جديدة واستخدمها في محادثة.',
    'اكتب رأيك في فيلم أو كتاب بالإنجليزية.',
    'تدرب على المضارع البسيط والماضي في جمل.',
    'اسمع مقطع صوتي وكرر ما سمعته.',
    'تعلّم كيف تسأل عن الأسعار والاتجاهات.',
    'اكتب قائمة مشترياتك بالإنجليزية.',
    'تعلّم أسماء الفواكه والخضروات.',
    'شاهد فيديو تعليمي على YouTube بالإنجليزية.',
    'تدرب على المحادثة الهاتفية بالإنجليزية.',
    'اقرأ نكتة بالإنجليزية وافهمها.',
    'تعلّم الفرق بين much و many و a lot of.',
    'اكتب بريداً إلكترونياً قصيراً بالإنجليزية.',
    'تعلّم 5 صفة إنجليزية جديدة.',
    'تدرب على speaking لدقيقة واحدة بدون توقف.',
    'اقرأ شعراً إنجليزياً قصيراً واحفظه.',
    'تعلّم عبارات الموافقة والمعارضة.',
    'شاهد فيديو TEDx قصير بالإنجليزية.',
    'اكتب ما تعلمته اليوم في 3 جمل إنجليزية.',
    'تعلّم كيفية التعريف عن نفسك بشكل احترافي.',
    'اقرأ تعليقات إنجليزية على منشورات وحاول تفهمها.',
    'تعلّم 3 اختصارات شائعة في الإنجليزية.',
  ];

  static const _behaviors = [
    'الصبر في التعلّم: التقدم خطوة بخطوة أفضل من القفز.',
    'الاستمرارية أهم من الكمال — تعلّم 10 دقائق يومياً أفضل من ساعة أسبوعياً.',
    'لا تخف من الأخطاء: كل خطأ درس جديد.',
    'استخدم الإنجليزية في حياتك اليومية حتى لو بسيطاً.',
    'اجعل هدفاً صغيراً يومياً وحققه.',
    'شارك ما تعلمته مع صديق — التعليم يُرسّخ المعرفة.',
    'اختر وقتاً ثابتاً للتعلّم يومياً.',
    'استمع أكثر مما تتكلم — الإصغاء يبني الفهم.',
    'لا تقارن نفسك بالآخرين، قارن نفسك بمن كنت بالأمس.',
    'استخدم خرائط ذهنية لتلخيص ما تتعلّمه.',
    'احتفظ بدفتر صغير لكتابة كلمات جديدة.',
    'تعلّم بالسياق: جمل كاملة أفضل من كلمات معزولة.',
    'اجعل التعلّم ممتعاً: استخدم ألعاباً وتطبيقات.',
    'خد استراحات قصيرة أثناء التدريب على اللغة.',
    'راقب تقدمك أسبوعياً واحتفل بالإنجازات الصغيرة.',
    'تواصل مع متعلمين آخرين للتشجيع.',
    'استخدم تقنية التعلم المتباعد: راجع ما تعلمته بعد يوم وأسبوع.',
    'ابدأ بالمواضيع التي تهمك في حياتك اليومية.',
    'لا تحفظ قواعد فقط — استخدم اللغة في جمل حقيقية.',
    'اكتب أفكارك بالإنجليزية قبل النوم.',
    'الاستماع للبودكاستات الإنجليزية يُحسّن فهمك بشكل كبير.',
    'اجعل هاتفك أداة تعلّم وليس فقط تسلية.',
    'تعلّم عبر الأغاني: الكلمات تعلق في الذاكرة.',
    'اكتب ملخصاً قصيراً لكل ما تتعلّمه.',
    'تحدث مع الذات بالإنجليزية يومياً.',
    'اتبع حسابات إنجليزية على وسائل التواصل.',
    'اقرأ العناوين الرئيسية للأخبار بالإنجليزية.',
    'ادّخر ميزانية زمنية للتعلّم يومياً.',
    'اجعل التعلّم جزءاً من روتينك اليومي.',
    'استخدم تقنية Pomodoro للتعلّم الفعال.',
    'الثقة بالنفس تأتي مع الممارسة — لا تنتظر الكمال.',
    'تعلّم من أخطائك ولا تكررها.',
    'اجعل بيئة تعلّم مريحة ومُحفّزة.',
    'استخدم البطاقات التعليمية للحفظ.',
    'راقب مستواك كل شهر.',
    'اجعل التعلّم عادة لا مهمة.',
    'شارك معرفتك وعلّم غيرك.',
    'استمع لأفلام إنجليزية بترجمة عربية أولاً ثم بدون.',
    'تحدى نفسك بمواضيع جديدة.',
    'اكتب يومياتك بالإنجليزية لمدة 30 يوماً.',
  ];

  static const _tips = [
    'نصيحة: استمع مرتين لنفس المقطع — مرة للمعنى ومرة للتفاصيل.',
    'نصيحة: احفظ الجملة أولاً ثم الكلمة — السياق يساعد الحفظ.',
    'نصيحة: اختر شخصية إنجليزية تحبها وتابعها.',
    'نصيحة: استخدم dictionary إنجليزي-إنجليزي بدلاً من عربي-إنجليزي.',
    'نصيحة: اكتب نصاً قصيراً يومياً واحذف الأخطاء بعد يومين.',
    'نصيحة: تعلم عبر اللعب — تطبيقات مثل Duolingo مساعدة.',
    'نصيحة: لا تحفظ القواعد — افهمها من الجمل.',
    'نصيحة: استخدم تقنية SQ3R للقراءة الفعّالة.',
    'نصيحة: ادرس 20 دقيقة صباحاً و 20 دقيقة مساءً.',
    'نصيحة: غيّر أسلوب التعلّم كل أسبوع.',
    'نصيحة: اكتب ملخصاً بـ 5 جمل لما تعلمته اليوم.',
    'نصيحة: استمع وأنت نائم لبودكاست إنجليزي.',
    'نصيحة: تعلم عبر الترجمة — ترجم فقرة وراجع ترجمتك.',
    'نصيحة: اجعل هاتفك يذكّرك بكلمة جديدة كل ساعة.',
    'نصيحة: تعلم الأفعال غير المنتظمة على مراحل.',
    'نصيحة: اكتب 3 جمل كل صباح قبل بدء يومك.',
    'نصيحة: احفظ عبارة جديدة كل يوم واستخدمها.',
    'نصيحة: شاهد أفلام أطفال بالإنجليزية للمبتدئين.',
    'نصيحة: اقرأ القصص القصيرة من graded readers.',
    'نصيحة: استخدم Google Translate لفحص نطقك.',
  ];

  static final _allIdeas = [..._ideas, ..._behaviors, ..._tips];

  static String forDate(DateTime date, {ReminderType type = ReminderType.idea, String interests = ''}) {
    if (interests.isNotEmpty) {
      final seed = date.year * 1000 + date.month * 100 + date.day;
      final rng = Random(seed);
      if (interests.contains('انجليزي') || interests.contains('English')) {
        const engIdeas = [
          '5 كلمات جديدة: (Effort, Achieve, Persistent, Unique, Valuable). حاول وضعها في جملة.',
          'قاعدة اليوم: استخدم "used to" للتعبير عن عادات قديمة انتهت.',
          'تحدي النطق: حاول نطق كلمة "Throughout" بشكل صحيح 5 مرات.',
          'استمع لمقطع قصير من BBC Learning English وطبق ما تعلمته.',
          'اكتب 3 جمل عن خططك لعطلة نهاية الأسبوع بالإنجليزية.',
        ];
        return engIdeas[rng.nextInt(engIdeas.length)];
      }
      if (interests.contains('تقنية') || interests.contains('Tech')) {
        const techIdeas = [
          'خبر ملهم: الذكاء الاصطناعي يساهم في اكتشاف علاجات جديدة للأمراض.',
          'نصيحة تقنية: جرب استخدام اختصارات الكيبورد لتسريع عملك اليومي.',
          'فكرة مشروع: برمج تطبيقاً بسيطاً يحل مشكلة صغيرة تواجهها.',
          'سلوك تقني: احرص على تحديث برامجك دورياً لحماية بياناتك.',
          'هل تعلم؟ لغة بايثون سُميت تيمناً بفرقة Monty Python الكوميدية.',
        ];
        return techIdeas[rng.nextInt(techIdeas.length)];
      }
      return 'بناءً على طلبك «$interests»: افتح ايفورا الآن لأسرد لك التفاصيل كاملة.';
    }
    final seed = date.year * 1000 + date.month * 100 + date.day;
    final rng = Random(seed);
    final pool = type == ReminderType.idea ? _allIdeas : _behaviors;
    return pool[rng.nextInt(pool.length)];
  }

  static String previewForType({ReminderType type = ReminderType.idea, String interests = ''}) {
    if (interests.isNotEmpty) {
      if (interests.contains('انجليزي') || interests.contains('English')) {
        return '5 كلمات جديدة: (Effort, Achieve, Persistent, Unique, Valuable). الجملة: "Consistent effort leads to valuable results."';
      }
      if (interests.contains('تقنية') || interests.contains('Tech')) {
        return 'خبر ملهم: تقنيات الواقع المعزز تبدأ في تغيير جذري لقطاع التعليم الطبي.';
      }
      return 'لا تفوّت هذا الإلهام عن «$interests» — افتح ايفورا للسرد.';
    }
    final rng = Random();
    final pool = type == ReminderType.idea ? _allIdeas : _behaviors;
    return pool[rng.nextInt(pool.length)];
  }
}

// ──────────────────────────────────────────────
//  خدمة التنبيهات
// ──────────────────────────────────────────────

class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  static const _prefsKey = 'aevora_reminder_prefs_v2';
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'aevora_reminders';
  static const _channelName = 'تنبيهات ايفورا';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
      if (!kIsWeb) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );
      }
    } catch (_) {}
  }

  static void _onNotificationResponse(NotificationResponse resp) {
    final payload = resp.payload;
    if (payload != null && payload.isNotEmpty) {
      _pendingPayload = payload;
    }
  }

  static String? _pendingPayload;
  static String? consumePayload() {
    final p = _pendingPayload;
    _pendingPayload = null;
    return p;
  }

  Future<ReminderPrefs> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return ReminderPrefs.fromJson(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (_) {}
    return const ReminderPrefs();
  }

  Future<ReminderItem?> getById(String id) async {
    final prefs = await load();
    try {
      return prefs.items.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(ReminderPrefs prefs) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsKey, jsonEncode(prefs.toJson()));
    } catch (_) {}
  }

  /// أيام الواجهة: 0=سبت … 6=جمعة. Dart: 1=اثنين … 7=أحد، 6=سبت.
  static int _uiDayToDartWeekday(int ui) {
    const map = [6, 7, 1, 2, 3, 4, 5];
    if (ui < 0 || ui > 6) return 6;
    return map[ui];
  }

  NotificationDetails _details({bool high = false}) => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'تنبيهات يومية للأفكار والمهام',
          importance: high ? Importance.max : Importance.high,
          priority: high ? Priority.max : Priority.high,
          icon: '@mipmap/ic_launcher',
          // sound: const RawResourceAndroidNotificationSound('aevora_sound'),
          // playSound: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          // sound: 'aevora_sound.wav',
        ),
      );

  Future<void> apply(ReminderPrefs prefs) async {
    try {
      await _plugin.cancelAll();
      for (final item in prefs.items.where((r) => r.enabled)) {
        final isIdea = item.type == ReminderType.idea;
        final title = isIdea ? 'ايفورا 💡' : 'ايفورا ✅';
        final body = isIdea
            ? (item.interests.isNotEmpty
                ? 'لا تفوّت هذا الإلهام — افتح التطبيق للسرد'
                : DailyContent.forDate(DateTime.now(), interests: item.interests))
            : (item.title.isNotEmpty
                ? 'تذكير: ${item.title}'
                : 'حان وقت مهمتك — افتح ايفورا');

        final days = item.days.isEmpty ? const [0, 1, 2, 3, 4, 5, 6] : item.days;
        for (final uiDay in days) {
          final dartDay = _uiDayToDartWeekday(uiDay);
          final when = _nextForWeekday(item.hour, item.minute, dartDay);
          final nid = (item.id.hashCode ^ (dartDay * 31)) & 0x7FFFFFFF;
          await _plugin.zonedSchedule(
            nid,
            title,
            body,
            when,
            _details(),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: item.id,
          );
        }
      }
    } catch (_) {}
  }

  tz.TZDateTime _nextForWeekday(int hour, int minute, int dartWeekday) {
    final now = tz.TZDateTime.now(tz.local);
    var candidate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    for (var i = 0; i < 8; i++) {
      if (candidate.weekday == dartWeekday && candidate.isAfter(now)) {
        return candidate;
      }
      candidate = candidate.add(const Duration(days: 1));
      candidate = tz.TZDateTime(
          tz.local, candidate.year, candidate.month, candidate.day, hour, minute);
    }
    return candidate;
  }

  Future<void> saveAndApply(ReminderPrefs prefs) async {
    await _save(prefs);
    await apply(prefs);
  }

  Future<void> testNotification(ReminderType type, {String interests = ''}) async {
    final content = DailyContent.previewForType(type: type, interests: interests);
    final title = type == ReminderType.idea ? 'ايفورا 💡 (اختبار)' : 'ايفورا ✅ (اختبار)';
    try {
      await _plugin.show(
        9999,
        title,
        content,
        _details(high: true),
        payload: 'test_${type.name}',
      );
    } catch (_) {}
  }
}

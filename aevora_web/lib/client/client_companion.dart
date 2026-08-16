import 'dart:async';
import 'dart:convert';

import 'client_llm.dart';
import 'client_storage.dart';
import 'client_sync.dart';
import 'client_usage.dart';

/// ذاكرة المساعد الشخصي: تعمل بالكامل داخل المتصفح.
/// تُحفظ الذكريات والمهام والمحادثات في IndexedDB على جهاز المستخدم.
class LocalCompanion {
  static const _kProfile = 'companion_profile';
  static const _kMemories = 'companion_memories';
  static const _kTasks = 'companion_tasks';
  static const _kMessages = 'companion_messages';
  static const _kProactiveDate = 'companion_proactive_date';
  static const _kProactive = 'companion_proactive';
  static const _kSummary = 'companion_summary';

  static String _date() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  static Future<Map<String, dynamic>> _getProfile() async {
    final v = await LocalDb.kvGetValue(_kProfile);
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  static Future<List<String>> _memories() async {
    final v = await LocalDb.kvGetValue(_kMemories);
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }

  static Future<List<Map<String, dynamic>>> _tasks() async {
    final v = await LocalDb.kvGetValue(_kTasks);
    if (v is List) {
      return v
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> _messages() async {
    final v = await LocalDb.kvGetValue(_kMessages);
    if (v is List) {
      return v
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return [];
  }

  static Future<void> _saveProfile(Map<String, dynamic> p) =>
      LocalDb.kvPut(_kProfile, p);
  static Future<void> _saveMessages(List<Map<String, dynamic>> m) =>
      LocalDb.kvPut(_kMessages, m);

  // ---------- تصدير/استيراد الحالة (للمزامنة مع الحساب) ----------

  /// لقطة كاملة لحالة المساعد تُرفع إلى السحابة مع الحساب.
  static Future<Map<String, dynamic>> exportState() async {
    return {
      'profile': await _getProfile(),
      'memories': await _memories(),
      'tasks': await _tasks(),
      'messages': await _messages(),
      'summary': (await LocalDb.kvGetValue(_kSummary) ?? '').toString(),
    };
  }

  /// تطبيق حالة قادمة من الحساب (عند تسجيل الدخول على جهاز جديد).
  /// لا تُنبّه للمزامنة هنا لتفادي حلقة رفع عند السحب.
  static Future<void> importState(Map<String, dynamic> state) async {
    final profile = state['profile'];
    if (profile is Map) await LocalDb.kvPut(_kProfile, profile);
    final memories = state['memories'];
    if (memories is List) await LocalDb.kvPut(_kMemories, memories);
    final tasks = state['tasks'];
    if (tasks is List) await LocalDb.kvPut(_kTasks, tasks);
    final messages = state['messages'];
    if (messages is List) await LocalDb.kvPut(_kMessages, messages);
    final summary = state['summary'];
    if (summary != null) {
      await LocalDb.kvPut(_kSummary, summary.toString());
    }
  }

  // ---------- الحالة ----------
  static Future<Map<String, dynamic>> loadState() async {
    final profile = await _getProfile();
    final proactive = await _currentProactive();
    return {
      'profile': profile,
      'memories': await _memories(),
      'tasks': await _tasks(),
      'recent': (await _messages()).reversed.take(50).toList().reversed.toList(),
      'summary': (await LocalDb.kvGetValue(_kSummary) ?? '').toString(),
      'proactive': proactive?['message'],
      'suggested_prompt': proactive?['prompt'],
    };
  }

  // ---------- المحادثة ----------
  static Future<String> streamReply({
    required String apiKey,
    required String message,
    void Function(String partial)? onChunk,
  }) async {
    final profile = await _getProfile();
    final memories = await _memories();
    final tasks = await _tasks();
    final all = await _messages();
    final recent = all.length <= 10 ? all : all.sublist(all.length - 10);

    final system = _buildSystemPrompt(profile, memories, tasks);

    final msgs = <ClientMsg>[
      for (final m in recent)
        ClientMsg(m['role'] == 'user' ? 'user' : 'model', m['text']?.toString() ?? ''),
      ClientMsg('user', message),
    ];

    final reply = await geminiStreamChat(
      apiKey: apiKey,
      messages: msgs,
      system: system,
      onChunk: onChunk,
      temperature: 0.7,
    );

    all
      ..add({'role': 'user', 'text': message})
      ..add({'role': 'model', 'text': reply});
    if (all.length > 300) {
      all.removeRange(0, all.length - 300);
    }
    await _saveMessages(all);

    final stats = Map<String, dynamic>.from(profile['learning_stats'] as Map? ?? {});
    stats['total_messages'] = all.length;
    profile['learning_stats'] = stats;
    await _saveProfile(profile);
    SyncStore.schedulePush();

    LocalUsage.recordCompanion();
    unawaited(_analyze(apiKey, message, reply));
    return reply;
  }

  static String _buildSystemPrompt(
    Map<String, dynamic> profile,
    List<String> memories,
    List<Map<String, dynamic>> tasks,
  ) {
    final parts = _memoryPromptParts(profile, memories, tasks);
    parts.add('لا تذكر هذه القائمة للمستخدم مباشرة؛ استخدمها خلف الكواليس فقط.');
    return parts.join('\n');
  }

  /// أجزاء ما يعرفه ايفورا عن المستخدم (اسم، مستوى، أهداف، اهتمامات، مفردات،
  /// تصحيحات، حقائق، مهام) — تُستخدم في المحادثة الموحّدة ورسالة الصديق.
  static List<String> _memoryPromptParts(
    Map<String, dynamic> profile,
    List<String> memories,
    List<Map<String, dynamic>> tasks,
  ) {
    final parts = <String>[
      'أنت «ايفورا»، المساعد الشخصي وصديق المستخدم لتحسين لغته الإنجليزية.',
      'تحدث دائماً باللغة العربية، وكن ودوداً وقصيراً وواضحاً.',
      'صحح أخطاء المستخدم اللغوية بلطف، وقدم كلمات وعبارات إنجليزية مفيدة مع شرحها.',
      'أنت تتعلم من المستخدم وتحفظ تفاصيله لتخصيص الردود.',
    ];
    final name = profile['name']?.toString();
    final level = profile['english_level']?.toString();
    if ((name ?? '').isNotEmpty || (level ?? '').isNotEmpty) {
      final bits = <String>[];
      if ((name ?? '').isNotEmpty) bits.add('الاسم: $name');
      if ((level ?? '').isNotEmpty) bits.add('المستوى: $level');
      parts.add('معرفتك عن المستخدم: ${bits.join('، ')}');
    }
    if (profile['goals'] is List && (profile['goals'] as List).isNotEmpty) {
      parts.add('أهدافه: ${(profile['goals'] as List).join('، ')}');
    }
    if (profile['interests'] is List && (profile['interests'] as List).isNotEmpty) {
      parts.add('اهتماماته: ${(profile['interests'] as List).join('، ')}');
    }
    if (profile['vocabulary'] is List && (profile['vocabulary'] as List).isNotEmpty) {
      parts.add('مفردات علمتها له سابقاً: ${(profile['vocabulary'] as List).join('، ')}');
    }
    if (profile['last_corrections'] is List &&
        (profile['last_corrections'] as List).isNotEmpty) {
      parts.add('آخر تصحيحات لغته: ${(profile['last_corrections'] as List).join('؛ ')}');
    }
    if (memories.isNotEmpty) {
      parts.add('حقائق يتذكرها عن المستخدم: ${memories.take(15).join('؛ ')}');
    }
    final open = tasks.where((t) => t['completed'] != true).toList();
    if (open.isNotEmpty) {
      parts.add('مهامه الحالية: ${open.map((t) => t['text']).join('، ')}');
    }
    return parts;
  }

  /// نظام المحادثة الموحّدة الذكية: يدمج ما يعرفه ايفورا عن المستخدم (اسم،
  /// مستوى، ذاكرة، مهام، مفردات، تصحيحات) مع سياق المستندات المرفوعة في تلقيم
  /// واحد — فيجيب عن الملفات وعن الأسئلة الشخصية والعامة في نفس المحادثة
  /// دون أن يضطر المستخدم للتبديل بين أقسام.
  static Future<String> buildUnifiedSystemPrompt({String docContext = ''}) async {
    final parts = _memoryPromptParts(
      await _getProfile(),
      await _memories(),
      await _tasks(),
    );
    if (docContext.trim().isNotEmpty) {
      parts.add(docContext.trim());
      parts.add('إذا كان السؤال عن المستندات المرفوعة فأجب منها بدقة ودون اختلاق '
          'وإن لم تجد الإجابة فيها فقل ذلك بوضوح. أما الأسئلة الشخصية أو العامة '
          'فأجب من معرفتك العامة.');
    }
    parts.add('لا تذكر هذه القائمة للمستخدم مباشرة؛ استخدمها خلف الكواليس فقط.');
    return parts.join('\n');
  }

  /// تحليل خلفي لمحادثة لاستخراج ما يستحق التذكّر (اسم، حقائق، مهام، مفردات،
  /// تصحيحات) — يُستدعى بعد كل رد في المحادثة الموحّدة.
  static Future<void> analyzeMessage(
    String apiKey,
    String userMsg,
    String reply,
  ) =>
      _analyze(apiKey, userMsg, reply);

  /// عدّاد التحليل الخلفي: يُجرى مرة كل ثلاث رسائل تقريباً بدل كل رسالة —
  /// كل رسالة كانت تستهلك طلب Gemini إضافياً خلف الكواليس فاستنزفت الحصة
  /// اليومية بلا فائدة تُذكر. الذاكرة لا تزال تُبنى، لكن بثلث الطلبات.
  static int _analyzeCounter = 0;

  /// تحليل خلفي للمحادثة لاستخراج ما يستحق التذكّر (اسم، حقائق، مهام، مفردات، تصحيحات).
  static Future<void> _analyze(String apiKey, String userMsg, String reply) async {
    _analyzeCounter++;
    if (_analyzeCounter % 3 != 0) return;
    try {
      final prompt = '''
اقرأ هذه المحادثة القصيرة بين المستخدم ومساعد اسمه ايفورا:
المستخدم: $userMsg
ايفورا: $reply

استخرج ما يستحق أن يتذكره ايفورا عن المستخدم، وأعد JSON فقط بهذا الشكل (لا شيء غيره):
{
  "new_memories": ["حقائق دائمة عن المستخدم مثل اسمه ومهنته ومكانه وأجهزته واهتماماته"],
  "new_tasks": [{"text": "مهمة طلبها المستخدم صراحة", "due": null}],
  "corrections": ["تصحيحات لغوية مهمة قدمها ايفورا"],
  "vocabulary": ["كلمات إنجليزية علمها ايفورا للمستخدم مع معناها"],
  "profile_updates": {"name": "", "english_level": "", "goals": [], "interests": []}
}
إن لم توجد معلومات جديدة أعد JSON فارغاً: {"new_memories":[],"new_tasks":[],"corrections":[],"vocabulary":[],"profile_updates":{}}
''';
      final out = await geminiChatSync(
        apiKey: apiKey,
        messages: [ClientMsg('user', prompt)],
        temperature: 0.2,
      );
      final json = _extractJson(out);
      if (json == null) return;
      await _applyAnalysis(json);
    } catch (_) {
      // فشل التحليل لا يعطّل المحادثة أبداً.
    }
  }

  static void _mergeUnique(List<String> list, Iterable<String> incoming, int cap) {
    for (final e in incoming) {
      final t = e.trim();
      if (t.isEmpty) continue;
      if (!list.any((x) => x == t)) list.add(t);
    }
    if (list.length > cap) list.removeRange(0, list.length - cap);
  }

  static Future<void> _applyAnalysis(Map<String, dynamic> json) async {
    final profile = await _getProfile();
    final memories = await _memories();
    final tasks = await _tasks();

    final newMem = (json['new_memories'] as List? ?? [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (newMem.isNotEmpty) {
      _mergeUnique(memories, newMem, 60);
      await LocalDb.kvPut(_kMemories, memories);
    }

    final newTasks = (json['new_tasks'] as List? ?? []).whereType<Map>();
    var added = false;
    for (final t in newTasks) {
      final text = (t['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      tasks.add({
        'id': '${DateTime.now().microsecondsSinceEpoch}_${tasks.length}',
        'text': text,
        'due': t['due']?.toString(),
        'completed': false,
      });
      added = true;
    }
    if (added) {
      if (tasks.length > 50) tasks.removeRange(0, tasks.length - 50);
      await LocalDb.kvPut(_kTasks, tasks);
    }

    final corr = (json['corrections'] as List? ?? [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (corr.isNotEmpty) {
      final existing = List<String>.from(profile['last_corrections'] as List? ?? []);
      _mergeUnique(existing, corr, 10);
      profile['last_corrections'] = existing;
    }

    final vocab = (json['vocabulary'] as List? ?? [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (vocab.isNotEmpty) {
      final existing = List<String>.from(profile['vocabulary'] as List? ?? []);
      _mergeUnique(existing, vocab, 40);
      profile['vocabulary'] = existing;
    }

    final pu = json['profile_updates'];
    if (pu is Map) {
      final name = (pu['name'] ?? '').toString().trim();
      if (name.isNotEmpty) profile['name'] = name;
      final level = (pu['english_level'] ?? '').toString().trim();
      if (level.isNotEmpty) profile['english_level'] = level;
      if (pu['goals'] is List && (pu['goals'] as List).isNotEmpty) {
        final incoming = (pu['goals'] as List).map((e) => e.toString().trim()).toList();
        final existing = List<String>.from(profile['goals'] as List? ?? []);
        _mergeUnique(existing, incoming, 20);
        profile['goals'] = existing;
      }
      if (pu['interests'] is List && (pu['interests'] as List).isNotEmpty) {
        final incoming = (pu['interests'] as List).map((e) => e.toString().trim()).toList();
        final existing = List<String>.from(profile['interests'] as List? ?? []);
        _mergeUnique(existing, incoming, 20);
        profile['interests'] = existing;
      }
    }
    await _saveProfile(profile);
    SyncStore.schedulePush();
  }

  // ---------- المهام ----------
  static Future<void> addTask(String text, {String? due}) async {
    final tasks = await _tasks();
    tasks.add({
      'id': '${DateTime.now().millisecondsSinceEpoch}_${tasks.length}',
      'text': text,
      'due': due,
      'completed': false,
    });
    await LocalDb.kvPut(_kTasks, tasks);
    SyncStore.schedulePush();
  }

  static Future<void> toggleTask(String id) async {
    final tasks = await _tasks();
    for (final t in tasks) {
      if (t['id'] == id) {
        t['completed'] = t['completed'] == true ? false : true;
      }
    }
    await LocalDb.kvPut(_kTasks, tasks);
    SyncStore.schedulePush();
  }

  static Future<void> deleteTask(String id) async {
    final tasks = await _tasks();
    tasks.removeWhere((t) => t['id'] == id);
    await LocalDb.kvPut(_kTasks, tasks);
    SyncStore.schedulePush();
  }

  static Future<void> reset() async {
    await LocalDb.kvDelete(_kProfile);
    await LocalDb.kvDelete(_kMemories);
    await LocalDb.kvDelete(_kTasks);
    await LocalDb.kvDelete(_kMessages);
    await LocalDb.kvDelete(_kSummary);
    await LocalDb.kvDelete(_kProactive);
    await LocalDb.kvDelete(_kProactiveDate);
    SyncStore.schedulePush();
  }

  // ---------- المبادرة اليومية ----------
  static Future<Map<String, dynamic>?> _currentProactive() async {
    final v = await LocalDb.kvGetValue(_kProactive);
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  /// توليد مبادرة يومية واحدة كحد أقصى (عند فتح المساعد).
  static Future<void> maybeGenerateProactive(String apiKey) async {
    final date = (await LocalDb.kvGetValue(_kProactiveDate) ?? '').toString();
    if (date == _date()) return;
    await LocalDb.kvPut(_kProactiveDate, _date());
    final memories = await _memories();
    if (memories.isEmpty) return;
    try {
      final prompt = '''
أنت ايفورا، صديق شخص يريد تحسين الإنجليزية.
ما تعرفه عنه: ${memories.take(8).join('؛ ')}
اقترح رسالة تشجيعية قصيرة (سطر أو سطران) له اليوم كصديق يهتم به، وأعد JSON فقط:
{"message":"الرسالة بالعربية","prompt":"اقتراح لبدء محادثة قصيرة بالإنجليزية مع معناها"}
''';
      final out = await geminiChatSync(
        apiKey: apiKey,
        messages: [ClientMsg('user', prompt)],
        temperature: 0.7,
      );
      final json = _extractJson(out);
      if (json != null && json['message'] != null) {
        await LocalDb.kvPut(_kProactive, {
          'message': json['message'],
          'prompt': json['prompt'],
        });
        SyncStore.schedulePush();
      }
    } catch (_) {}
  }

  static Future<void> acknowledgeProactive() async {
    await LocalDb.kvDelete(_kProactive);
    await LocalDb.kvPut(_kProactiveDate, _date());
    SyncStore.schedulePush();
  }
}

Map<String, dynamic>? _extractJson(String s) {
  var t = s.trim();
  final start = t.indexOf('{');
  final end = t.lastIndexOf('}');
  if (start >= 0 && end > start) t = t.substring(start, end + 1);
  try {
    final obj = jsonDecode(t);
    if (obj is Map) return Map<String, dynamic>.from(obj);
  } catch (_) {}
  return null;
}

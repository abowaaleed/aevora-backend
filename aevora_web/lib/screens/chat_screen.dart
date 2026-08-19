import 'dart:async';
import 'dart:io' if (kIsWeb) '';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import '../client/client_companion.dart';
import '../client/client_export.dart';
import '../client/client_handoff.dart';
import '../client/client_llm.dart';
import '../client/client_plan.dart';
import '../client/client_rag.dart';
import '../client/client_storage.dart';
import '../client/client_sync.dart';
import '../client/client_voice.dart';
import '../config.dart';
import '../widgets/export_sheet.dart';

/// المحادثة الموحّدة الذكية: تجيب عن الأسئلة عن المستندات المرفوعة وعن
/// الأسئلة الشخصية والعامة (السلوك، التعليم، أي شيء) في محادثة واحدة —
/// لا يختار المستخدم بين «محادثة» و«صديق» بعد الآن.
class ChatScreen extends StatefulWidget {
  final KeySettings keys;
  const ChatScreen({super.key, required this.keys});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatMessage {
  final String id;
  String text;
  final bool isUser;
  _ChatMessage(this.text, this.isUser, {String? id})
      : id = id ??
            '${DateTime.now().microsecondsSinceEpoch}_${text.hashCode}';
}

class _ChatScreenState extends State<ChatScreen> {
  static const _green = Color(0xFF4CAF50);

  final TextEditingController _input = TextEditingController();
  final List<_ChatMessage> _messages = [];
  final ScrollController _scroll = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  final AudioRecorder _recorder = AudioRecorder();

  bool _isLoading = false;
  bool _isListening = false;
  bool _isThinking = false;
  bool _showDownButton = false;

  String? _name;
  String? _level;
  int _taskCount = 0;
  List<Map<String, dynamic>> _tasks = [];
  List<String> _memories = [];
  List<String> _goals = [];
  List<String> _vocab = [];
  List<String> _corrections = [];
  String? _proactive;
  String? _suggestedPrompt;
  bool _proactiveDismissed = false;
  bool _hideTasksPanel = true;
  bool _hideMemoryPanel = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScrollChanged);
    _inputFocus.addListener(_onInputFocus);
    SyncStore.chatReloadTick.addListener(_onCloudReload);
    ChatHandoff.pendingPrompt.addListener(_onHandoffPrompt);
    _loadHistory();
    _refreshCompanion();
    _maybeProactive();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onHandoffPrompt());
  }

  @override
  void dispose() {
    ChatHandoff.pendingPrompt.removeListener(_onHandoffPrompt);
    SyncStore.chatReloadTick.removeListener(_onCloudReload);
    _scroll.removeListener(_onScrollChanged);
    _inputFocus.removeListener(_onInputFocus);
    _inputFocus.dispose();
    _input.dispose();
    _scroll.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _onInputFocus() {
    if (_inputFocus.hasFocus) {
      _scrollToBottom(force: true);
    }
  }

  void _onHandoffPrompt() {
    final p = ChatHandoff.pendingPrompt.value;
    if (p == null || p.trim().isEmpty) return;
    ChatHandoff.pendingPrompt.value = null;
    unawaited(_send(p.trim()));
  }

  bool get _nearBottom {
    if (!_scroll.hasClients) return true;
    final pos = _scroll.position;
    return pos.maxScrollExtent - pos.pixels < 120;
  }

  void _onScrollChanged() {
    final show = !_nearBottom;
    if (show != _showDownButton && mounted) {
      setState(() => _showDownButton = show);
    }
  }

  Future<void> _loadHistory() async {
    try {
      final v = await LocalDb.kvGetValue('chat_messages');
      if (v is List && v.isNotEmpty) {
        final knownIds = <String>{};
        final msgs = v
            .whereType<Map>()
            .map((m) => _ChatMessage((m['text'] ?? '').toString(),
                m['role'] == 'user', id: (m['id'] ?? '').toString()))
            .where((m) => m.text.trim().isNotEmpty)
            .where((m) => knownIds.add(m.id))
            .toList();
        if (msgs.isNotEmpty && mounted) {
          setState(() => _messages.addAll(msgs));
          _scrollToBottom();
          return;
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _messages.add(_ChatMessage(
          'مرحباً بك في ايفورا! 👋\n\nاسألني عن مستنداتك المرفوعة (من قسم «مستندات»)، '
          'أو احكِ لي عن يومك، أو اسألني عن السلوك والتعليم وأي شيء — '
          'كل ذلك في محادثة واحدة وسأتذكر ما يهمك.',
          false,
        ));
      });
    }
  }

  Future<void> _maybeProactive() async {
    try {
      await LocalCompanion.maybeGenerateProactive(widget.keys.geminiKey);
    } catch (_) {}
    await _refreshCompanion();
  }

  /// تحميل ما يعرفه ايفورا عن المستخدم (الاسم، المستوى، الذاكرة، المهام)
  /// لعرضها في الرأس ولوحات المساعد.
  Future<void> _refreshCompanion() async {
    try {
      final s = await LocalCompanion.loadState();
      if (!mounted) return;
      setState(() {
        _name = s['profile']?['name'] as String?;
        _level = s['profile']?['english_level'] as String?;
        _memories = (s['memories'] as List?)?.cast<String>() ?? [];
        _goals = (s['profile']?['goals'] as List?)?.cast<String>() ?? [];
        _vocab = (s['profile']?['vocabulary'] as List?)?.cast<String>() ?? [];
        _corrections =
            (s['profile']?['last_corrections'] as List?)?.cast<String>() ?? [];
        _tasks = (s['tasks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _taskCount = _tasks.where((t) => t['completed'] != true).length;
        if (!_proactiveDismissed) {
          _proactive = s['proactive'] as String?;
          _suggestedPrompt = s['suggested_prompt'] as String?;
        }
      });
    } catch (_) {}
  }

  Future<void> _dismissProactive() async {
    setState(() {
      _proactive = null;
      _suggestedPrompt = null;
      _proactiveDismissed = true;
    });
    try {
      await LocalCompanion.acknowledgeProactive();
    } catch (_) {}
  }

  Future<void> _toggleTask(Map<String, dynamic> task) async {
    try {
      await LocalCompanion.toggleTask(task['id'] as String);
    } catch (_) {}
    await _refreshCompanion();
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    try {
      await LocalCompanion.deleteTask(task['id'] as String);
    } catch (_) {}
    await _refreshCompanion();
  }

  Future<void> _addTask() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141A2A),
        title:
            const Text('أضف مهمة تذكّرني بها', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.rtl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'اكتب المهمة...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('حفظ', style: TextStyle(color: _green)),
          ),
        ],
      ),
    );
    if (text != null && text.isNotEmpty) {
      try {
        await LocalCompanion.addTask(text);
      } catch (_) {}
      await _refreshCompanion();
    }
  }

  Future<void> _resetMemory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141A2A),
        title: const Text('مسح ذاكرة المساعد؟', style: TextStyle(color: Colors.white)),
        content: const Text(
            'سيُمسح كل ما يعرفه عنك: اسمك، ذاكرته، مهامك، وسجل المحادثة. لا يمكن التراجع.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('امسح', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await LocalCompanion.reset();
        await LocalDb.kvDelete('chat_messages');
      } catch (_) {}
      _proactiveDismissed = false;
      if (mounted) {
        setState(() {
          _messages
            ..clear()
            ..add(_ChatMessage(
              'تم مسح المحادثة والذاكرة. ابدأ من جديد متى شئت.',
              false,
            ));
        });
      }
      await _persistMessages();
      await _refreshCompanion();
    }
  }

  String _buildSubtitle() {
    final parts = <String>[];
    if (_name != null && _name!.isNotEmpty) parts.add(_name!);
    if (_level != null && _level!.isNotEmpty) parts.add(_level!);
    if (parts.isEmpty) return 'اسألني عن ملفاتك أو عن أي شيء';
    return parts.join(' · ');
  }

  /// عند تطبيق محادثة قادمة من السحابة (جهاز/تبويب آخر): نضيف الرسائل
  /// المفقودة فقط دون مسح ما في الواجهة حالياً — حتى لا تختفي رسالة أبداً.
  void _onCloudReload() {
    if (!mounted) return;
    unawaited(_mergeFromStore());
  }

  Future<void> _mergeFromStore() async {
    try {
      final v = await LocalDb.kvGetValue('chat_messages');
      if (v is! List) return;
      final knownIds = <String>{for (final m in _messages) m.id};
      final adds = <_ChatMessage>[];
      for (final raw in v.whereType<Map>()) {
        final text = (raw['text'] ?? '').toString();
        if (text.trim().isEmpty) continue;
        final role = (raw['role'] ?? '').toString();
        final id = (raw['id'] ?? '').toString();
        final msg =
            _ChatMessage(text, role == 'user', id: id.isEmpty ? null : id);
        if (knownIds.contains(msg.id)) continue;
        knownIds.add(msg.id);
        adds.add(msg);
      }
      if (adds.isNotEmpty && mounted) {
        setState(() => _messages.addAll(adds));
        _scrollToBottom();
      }
    } catch (_) {}
  }

  Future<void> _persistMessages() async {
    try {
      final list = _messages
          .where((m) => m.text.trim().isNotEmpty)
          .map((m) =>
              {'id': m.id, 'role': m.isUser ? 'user' : 'model', 'text': m.text})
          .toList();
      if (list.length > 100) {
        list.removeRange(0, list.length - 100);
      }
      // دمج مع الحالة المخزنة بدل استبدالها: لو جرت كتابة قبل اكتمال تحميل
      // التاريخ (سباق عند فتح التطبيق) لا تُمسح الرسائل المحفوظة سابقاً.
      final existing = await LocalDb.kvGetValue('chat_messages');
      await LocalDb.kvPut('chat_messages', mergeChatMessages(existing, list));
      SyncStore.schedulePush();
    } catch (_) {}
  }

  void _scrollToBottom({bool force = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (!force && !_nearBottom) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send(String text, {bool speakReply = false}) async {
    if (text.trim().isEmpty || _isLoading) return;
    warmUpAudio();
    _inputFocus.unfocus();
    setState(() {
      _messages.add(_ChatMessage(text, true));
      _isLoading = true;
      _input.clear();
    });
    _scrollToBottom(force: true);
    // حفظ فوري لرسالة المستخدم لحظة الإرسال حتى لا تختفي أبداً عند أي
    // إعادة إنشاء للشاشة (تحديث جلسة/توجيه).
    await _persistMessages();

    final assistant = _ChatMessage('', false);
    setState(() => _messages.add(assistant));

    var system = await LocalCompanion.buildUnifiedSystemPrompt();
    try {
      if (await hasFiles()) {
        final chunks = await retrieveChunks(text, k: 6);
        final ctx = buildContextPrompt(chunks);
        if (ctx.isNotEmpty) {
          system = await LocalCompanion.buildUnifiedSystemPrompt(docContext: ctx);
        }
      }
    } catch (_) {}

    try {
      final history = _messages
          .where((m) => m.text.trim().isNotEmpty)
          .toList();
      final trimmed =
          history.length <= 20 ? history : history.sublist(history.length - 20);
      final msgs = [
        for (final m in trimmed) ClientMsg(m.isUser ? 'user' : 'model', m.text),
      ];

    String reply;
    try {
      reply = await geminiStreamChat(
        apiKey: widget.keys.geminiKey,
        messages: msgs,
        system: system,
        onChunk: (partial) {
          assistant.text += partial;
          if (mounted) setState(() {});
          _scrollToBottom();
        },
      );
      activeChatEngine.value = ChatEngine.gemini;
    } catch (e) {
      // الربط السلس مع Groq: إذا تعذّر Gemini (نفاد حصة/ازدحام/خطأ) ووُجد
      // مفتاح Groq، تنتقل المحادثة إليه تلقائياً وبصمت — التطبيق لا يتوقف.
      // إن كان Gemini قد بدأ الرد جزئياً ثم انقطع، نمسح الجزء قبل التحويل.
      final groqKey = widget.keys.groqKey.trim();
      if (groqKey.isEmpty) rethrow;
      assistant.text = '';
      reply = await groqChatStream(
        apiKey: groqKey,
        messages: msgs,
        system: system,
        onChunk: (partial) {
          assistant.text += partial;
          if (mounted) setState(() {});
          _scrollToBottom();
        },
      );
      activeChatEngine.value = ChatEngine.groq;
    }
    assistant.text = reply;
      if (mounted) setState(() {});
      _scrollToBottom();
      await _persistMessages();
      // استخراج ما يستحق التذكّر (اسم، حقائق، مهام، مفردات، تصحيحات) من
      // هذه المحادثة — في الخلفية دون إبطاء الواجهة.
      unawaited(LocalCompanion.analyzeMessage(
          widget.keys.geminiKey, text, reply));
      unawaited(_refreshCompanion());
      // إنهاء حالة الانشغال فوراً قبل النطق حتى لا تُعلَّق الواجهة على توليد
      // الصوت؛ النطق التلقائي يعمل بالتوازي ولا يحجب أي زر.
      if (mounted) setState(() => _isLoading = false);
      if (speakReply) {
        unawaited(_speakAuto(reply, messageId: assistant.id));
      }
    } catch (e) {
      // رسالة ودّية بدل «خطأ: Exception: ...» التقنية — لا نعرض للمستخدم
      // نصاً خاماً مخيفاً، بل صياغة لطيفة تناسب طبيعة المحادثة.
      assistant.text = friendlyError(e);
      if (mounted) setState(() {});
      await _persistMessages();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _speakAuto(String text, {required String messageId}) async {
    await PlaybackController.instance.play(
      text,
      apiKey: widget.keys.geminiKey,
      messageId: messageId,
    );
  }

  Future<void> _toggleVoice() async {
    if (_isListening) {
      await _stopAndTranscribe();
      return;
    }
    warmUpAudio();
    try {
      if (!await _recorder.hasPermission()) {
        _addError('تم رفض إذن الميكروفون.');
        return;
      }
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000),
        path: 'evora_voice.wav',
      );
      if (mounted) setState(() => _isListening = true);
    } catch (_) {
      _addError('تعذّر بدء التسجيل — تحقق من إذن الميكروفون.');
    }
  }

  Future<void> _stopAndTranscribe() async {
    try {
      final path = await _recorder.stop();
      if (mounted) setState(() => _isListening = false);
      if (path == null) return;

      if (mounted) setState(() => _isThinking = true);

      Uint8List audioBytes;
      if (kIsWeb) {
        audioBytes = (await http.get(Uri.parse(path))).bodyBytes;
      } else {
        audioBytes = await File(path).readAsBytes();
      }

      final text = await groqTranscribe(
        apiKey: widget.keys.groqKey,
        wavBytes: audioBytes,
      );
      if (mounted) setState(() => _isThinking = false);
      await _send(text, speakReply: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isThinking = false;
          _isListening = false;
        });
      }
      _addError('لم نستطع سماعك هذه المرة، أعد المحاولة.');
    }
  }

  void _addError(String msg) {
    if (!mounted) return;
    setState(() => _messages.add(_ChatMessage(msg, false)));
  }

  Future<void> _exportChat() async {
    final msgs = _messages
        .where((m) => m.text.trim().isNotEmpty)
        .map((m) => {'role': m.isUser ? 'user' : 'model', 'text': m.text})
        .toList();
    // الخطة المدفوعة تصدر المحادثة دون الترويج التلقائي.
    final text = buildExportText(msgs,
        includePromo: !PlanStore.current.value.isPremium);
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    await showExportSheet(context, text: text, filename: 'aevora_chat_$stamp.txt');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF070B14),
        resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          SafeArea(bottom: false, child: _topBar()),
          if (_proactive != null && !_proactiveDismissed) _proactiveCard(),
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  controller: _scroll,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_hasExtraPanels() ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_hasExtraPanels() && index == _messages.length) {
                      return _infoPanels();
                    }
                    final m = _messages[index];
                    return _MessageBubble(
                      message: m,
                      playingId: PlaybackController.instance.activeId,
                      onSpeak: (id, rate) =>
                          PlaybackController.instance.play(
                        m.text,
                        apiKey: widget.keys.geminiKey,
                        rate: rate == '-25%' ? 0.75 : 1.0,
                        messageId: id,
                      ),
                      onStop: () async => PlaybackController.instance.stop(),
                    );
                  },
                ),
                if (_showDownButton)
                  Positioned(
                    right: 14,
                    bottom: 10,
                    child: FloatingActionButton.small(
                      heroTag: 'chat_down',
                      backgroundColor: const Color(0xFF1D3A1D),
                      foregroundColor: Colors.white,
                      onPressed: () {
                        setState(() => _showDownButton = false);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scroll.hasClients) {
                            _scroll.animateTo(
                              _scroll.position.maxScrollExtent,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        });
                      },
                      tooltip: 'الانتقال لآخر رسالة',
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ),
              ],
            ),
          ),
          if (_isThinking)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _green),
                  ),
                  SizedBox(width: 8),
                  Text('جاري تفريغ الصوت...',
                      style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                ],
              ),
            ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _green),
                  ),
                  SizedBox(width: 8),
                  Text('ايفورا تكتب...',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          SafeArea(top: false, child: _inputBar()),
        ],
      ),
    ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      color: const Color(0xFF0D1424),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF1D3A1D),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: _green, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ايفورا — المساعد الذكي',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(_buildSubtitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                onPressed: _exportChat,
                tooltip: 'تصدير المحادثة مع ترويج ايفورا',
                icon: const Icon(Icons.ios_share_rounded, color: Colors.white70),
              ),
              IconButton(
                onPressed: _resetMemory,
                tooltip: 'مسح الذاكرة',
                icon: const Icon(Icons.delete_sweep_outlined,
                    color: Colors.white38, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _engineChip(),
                _clickableChip(
                  Icons.memory_rounded,
                  'ذاكرة: ${_memories.length}',
                  active: !_hideMemoryPanel,
                  onTap: () => setState(() => _hideMemoryPanel = !_hideMemoryPanel),
                ),
                _clickableChip(
                  Icons.task_alt_rounded,
                  'مهام: $_taskCount',
                  active: !_hideTasksPanel,
                  onTap: () => setState(() => _hideTasksPanel = !_hideTasksPanel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// مؤشر المحرك الحالي: نقطة خضراء مشعّة بجانب اسم النموذج الذي يجيب الآن
  /// (جيميناي بشكل افتراضي، وتنتقل إلى Groq تلقائياً عند تعذّر جيميناي).
  Widget _engineChip() {
    return ValueListenableBuilder<ChatEngine>(
      valueListenable: activeChatEngine,
      builder: (context, engine, _) {
        final isGemini = engine == ChatEngine.gemini;
        final label = isGemini ? 'جيميناي' : 'Groq';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _green.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _glowingDot(),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        );
      },
    );
  }

  /// دائرة خضراء مشعّة (توهج) تدل على أن المحرك يعمل الآن.
  Widget _glowingDot() {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: _green,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _green.withValues(alpha: 0.9),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _clickableChip(IconData icon, String label,
      {required bool active, required VoidCallback onTap}) {
    return Tooltip(
      message: active ? 'إخفاء' : 'إظهار',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? _green.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: active ? Border.all(color: _green.withValues(alpha: 0.4)) : null,
          ),
          child: Row(
            children: [
              Icon(icon, color: active ? _green : Colors.white54, size: 13),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: active ? _green : Colors.white70, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _proactiveCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(colors: [Color(0xFF1D3A1D), Color(0xFF14292A)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.waving_hand_rounded, color: Colors.amber, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('لحظة من ايفورا',
                    style: TextStyle(
                        color: _green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
              GestureDetector(
                onTap: _dismissProactive,
                child:
                    const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_proactive ?? '', style: const TextStyle(color: Colors.white, height: 1.5)),
          if (_suggestedPrompt != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _isLoading
                    ? null
                    : () {
                        _dismissProactive();
                        _send(_suggestedPrompt!);
                      },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.auto_awesome_rounded, color: _green, size: 16),
                label: const Text('ابدأ الآن'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _hasExtraPanels() {
    final showTasks = !_hideTasksPanel && _tasks.isNotEmpty;
    final showMemory = !_hideMemoryPanel && _hasMemoryContent();
    return showTasks || showMemory;
  }

  bool _hasMemoryContent() {
    return _memories.isNotEmpty ||
        _goals.isNotEmpty ||
        _vocab.isNotEmpty ||
        _corrections.isNotEmpty;
  }

  Widget _infoPanels() {
    final children = <Widget>[];
    if (!_hideTasksPanel && _tasks.isNotEmpty) {
      children.add(_tasksPanel());
      children.add(const SizedBox(height: 10));
    }
    if (!_hideMemoryPanel && _hasMemoryContent()) {
      children.add(_memoryPanel());
      children.add(const SizedBox(height: 10));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _tasksPanel() {
    return _panelCard(
      icon: Icons.task_alt_rounded,
      title: 'مهامك',
      onClose: () => setState(() => _hideTasksPanel = true),
      actions: InkWell(
        onTap: _addTask,
        child:
            const Icon(Icons.add_circle_outline_rounded, color: _green, size: 20),
      ),
      child: Column(children: [for (final t in _tasks) _taskRow(t)]),
    );
  }

  Widget _taskRow(Map<String, dynamic> t) {
    final done = t['completed'] == true;
    return Row(
      children: [
        Checkbox(value: done, activeColor: _green, onChanged: (_) => _toggleTask(t)),
        Expanded(
          child: InkWell(
            onTap: () => _toggleTask(t),
            child: Text(t['text'] as String? ?? '',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white38)),
          ),
        ),
        IconButton(
          onPressed: () => _deleteTask(t),
          icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white38),
        ),
      ],
    );
  }

  Widget _memoryPanel() {
    final items = <String>[];
    for (final g in _goals) {
      items.add('🎯 $g');
    }
    items.addAll(_memories.map((m) => '🧠 $m'));
    items.addAll(_vocab.map((v) => '📘 $v'));
    items.addAll(_corrections.map((c) => '✏️ $c'));
    return _panelCard(
      icon: Icons.memory_rounded,
      title: 'ما أعرفه عنك (${items.length})',
      onClose: () => setState(() => _hideMemoryPanel = true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items.take(12))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(item,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
          if (items.length > 12)
            const Text('والمزيد...', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _panelCard({
    required IconData icon,
    required String title,
    required Widget child,
    VoidCallback? onClose,
    Widget? actions,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFF141A2A), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _green, size: 17),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (actions != null) ...[
                actions,
                const SizedBox(width: 6),
              ],
              if (onClose != null)
                Tooltip(
                  message: 'إخفاء',
                  child: InkWell(
                    onTap: onClose,
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white38, size: 20),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: const Color(0xFF0D1424),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _inputFocus,
              textDirection: TextDirection.rtl,
              style: const TextStyle(color: Colors.white, height: 1.5),
              keyboardType: TextInputType.multiline,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onTap: () => _scrollToBottom(force: true),
              onTapOutside: (_) => _inputFocus.unfocus(),
              onSubmitted: (v) => _send(v),
              decoration: InputDecoration(
                hintText: 'اكتب سؤالك...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF141A2A),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _isLoading ? null : _toggleVoice,
            style: IconButton.styleFrom(
              backgroundColor: _isListening
                  ? Colors.redAccent
                  : _isThinking
                      ? Colors.amber
                      : const Color(0xFF1D3A1D),
            ),
            icon: Icon(
              _isListening
                  ? Icons.stop_circle_rounded
                  : _isThinking
                      ? Icons.hourglass_top
                      : Icons.mic_none,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _isLoading ? null : () => _send(_input.text),
            style: IconButton.styleFrom(backgroundColor: _green),
            icon: const Icon(Icons.send_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final _ChatMessage message;
  final ValueNotifier<String?> playingId;
  final Future<void> Function(String id, String? rate) onSpeak;
  final Future<void> Function() onStop;
  const _MessageBubble({
    required this.message,
    required this.playingId,
    required this.onSpeak,
    required this.onStop,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  static const _green = Color(0xFF4CAF50);

  bool _copied = false;
  bool _playingNormal = false;
  bool _playingSlow = false;

  @override
  void initState() {
    super.initState();
    widget.playingId.addListener(_onPlayingChanged);
  }

  @override
  void dispose() {
    widget.playingId.removeListener(_onPlayingChanged);
    super.dispose();
  }

  void _onPlayingChanged() {
    if (mounted) setState(() {});
  }

  bool get _isPlaying => widget.playingId.value == widget.message.id;

  Future<void> _copy() async {
    // شارة RLM تُلزم برنامج Word بعرض النص من اليمين إلى اليسار عند اللصق.
    await Clipboard.setData(ClipboardData(text: '\u200F${widget.message.text}'));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _play({bool slow = false}) async {
    if (_isPlaying) {
      setState(() {
        _playingNormal = false;
        _playingSlow = false;
      });
      await widget.onStop();
      return;
    }
    setState(() {
      if (slow) {
        _playingSlow = true;
        _playingNormal = false;
      } else {
        _playingNormal = true;
        _playingSlow = false;
      }
    });
    await widget.onSpeak(widget.message.id, slow ? '-25%' : '+0%');
    if (mounted) {
      setState(() {
        _playingNormal = false;
        _playingSlow = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: m.isUser ? Alignment.centerLeft : Alignment.centerRight,
        child: Column(
          crossAxisAlignment:
              m.isUser ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: BoxDecoration(
                color: m.isUser ? const Color(0xFF1D3A1D) : const Color(0xFF141A2A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                m.text,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, height: 1.6, fontSize: 15),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(
                  icon: _playingNormal
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                        )
                      : Icon(
                          _isPlaying ? Icons.stop_rounded : Icons.volume_up_rounded,
                          size: 16,
                          color: _isPlaying ? _green : Colors.white54,
                        ),
                  onPressed: () => _play(),
                  tooltip: 'استماع',
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: _playingSlow
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                        )
                      : const Icon(Icons.speed_rounded, size: 16, color: Colors.white54),
                  onPressed: () => _play(slow: true),
                  tooltip: 'استماع ببطء',
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.content_copy_rounded,
                    size: 16,
                    color: _copied ? _green : Colors.white54,
                  ),
                  onPressed: _copy,
                  tooltip: 'نسخ',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  const _ActionButton({required this.icon, this.onPressed, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: icon,
        ),
      ),
    );
  }
}

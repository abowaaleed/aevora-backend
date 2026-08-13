import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import '../client/client_export.dart';
import '../client/client_llm.dart';
import '../client/client_rag.dart';
import '../client/client_storage.dart';
import '../client/client_sync.dart';
import '../client/client_voice.dart';
import '../config.dart';
import '../widgets/export_sheet.dart';
import '../widgets/plain_text_paste_dialog.dart';

const _chatSystemPrompt = '''
أنت «ايفورا» — مساعد ذكي يجيب بلغة المستخدم (العربية أو الإنجليزية).
إذا وُجدت مقتطفات من مستندات مرفوعة، أجب منها بدقة ودون اختلاق.
إن لم تجد الإجابة في المستندات فقل ذلك بوضوح.
''';

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
  _ChatMessage(this.text, this.isUser)
      : id = '${DateTime.now().microsecondsSinceEpoch}_${text.hashCode}';
}

class _ChatScreenState extends State<ChatScreen> {
  static const _green = Color(0xFF4CAF50);

  final TextEditingController _input = TextEditingController();
  final List<_ChatMessage> _messages = [];
  final ScrollController _scroll = ScrollController();

  final AudioRecorder _recorder = AudioRecorder();
  final ValueNotifier<String?> _playingId = ValueNotifier<String?>(null);

  bool _isLoading = false;
  bool _isListening = false;
  bool _isThinking = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _recorder.dispose();
    _playingId.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final v = await LocalDb.kvGetValue('chat_messages');
      if (v is List && v.isNotEmpty) {
        final msgs = v
            .whereType<Map>()
            .map((m) => _ChatMessage(
                (m['text'] ?? '').toString(), m['role'] == 'user'))
            .where((m) => m.text.trim().isNotEmpty)
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
          'مرحباً بك في ايفورا!\n\nارفع مستنداتك من تبويب «المستندات» ثم اسألني عنها، أو اسألني مباشرة بأي لغة.',
          false,
        ));
      });
    }
  }

  Future<void> _persistMessages() async {
    try {
      final list = _messages
          .where((m) => m.text.trim().isNotEmpty)
          .map((m) => {'role': m.isUser ? 'user' : 'model', 'text': m.text})
          .toList();
      if (list.length > 100) {
        list.removeRange(0, list.length - 100);
      }
      await LocalDb.kvPut('chat_messages', list);
      SyncStore.schedulePush();
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _isLoading) return;
    // إنشاء سياق الصوت داخل إيماءة المستخدم حتى يبدأ النطق الاحترافي فوراً
    // بعد الرد دون أن تحجبه سياسة التشغيل التلقائي.
    warmUpAudio();
    setState(() {
      _messages.add(_ChatMessage(text, true));
      _isLoading = true;
      _input.clear();
    });
    _scrollToBottom();
    // حفظ فوري لرسالة المستخدم لحظة الإرسال حتى لا تختفي أبداً عند أي
    // إعادة إنشاء للشاشة (تحديث جلسة/توجيه).
    await _persistMessages();

    final assistant = _ChatMessage('', false);
    setState(() => _messages.add(assistant));

    var system = _chatSystemPrompt;
    try {
      if (await hasFiles()) {
        final chunks = await retrieveChunks(text, k: 6);
        final ctx = buildContextPrompt(chunks);
        if (ctx.isNotEmpty) system = '$_chatSystemPrompt\n\n$ctx';
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

      final reply = await geminiStreamChat(
        apiKey: widget.keys.geminiKey,
        messages: msgs,
        system: system,
        onChunk: (partial) {
          assistant.text += partial;
          if (mounted) setState(() {});
          _scrollToBottom();
        },
      );
      assistant.text = reply;
      if (mounted) setState(() {});
      _scrollToBottom();
      await _persistMessages();
      // إنهاء حالة الانشغال فوراً قبل النطق حتى لا تُعلَّق الواجهة على توليد
      // الصوت؛ النطق التلقائي يعمل بالتوازي ولا يحجب أي زر.
      if (mounted) setState(() => _isLoading = false);
      unawaited(_speak(reply, messageId: assistant.id));
    } catch (e) {
      assistant.text = 'خطأ: $e';
      if (mounted) setState(() {});
      await _persistMessages();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _speak(String text, {required String messageId, String? rate}) async {
    if (text.isEmpty) return;
    try {
      if (_playingId.value == messageId) {
        stopSpeaking();
        _playingId.value = null;
        return;
      }
      stopSpeaking();
      _playingId.value = messageId;
      await speakSmart(text,
          apiKey: widget.keys.geminiKey, rate: rate == '-25%' ? 0.75 : 1.0);
      _playingId.value = null;
    } catch (_) {
      _playingId.value = null;
    }
  }

  Future<void> _stopPlayback() async {
    stopSpeaking();
    _playingId.value = null;
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
    } catch (e) {
      _addError('فشل بدء التسجيل: $e');
    }
  }

  Future<void> _stopAndTranscribe() async {
    try {
      final path = await _recorder.stop();
      if (mounted) setState(() => _isListening = false);
      if (path == null) return;

      if (mounted) setState(() => _isThinking = true);
      final audioBytes = (await http.get(Uri.parse(path))).bodyBytes;

      final text = await groqTranscribe(
        apiKey: widget.keys.groqKey,
        wavBytes: audioBytes,
      );
      if (mounted) setState(() => _isThinking = false);
      await _send(text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isThinking = false;
          _isListening = false;
        });
      }
      _addError('خطأ في الصوت: $e');
    }
  }

  Future<void> _openPlainTextPaste() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const PlainTextPasteDialog(),
    );
    if (text != null && text.isNotEmpty) {
      await _send(text);
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
    final text = buildExportText(msgs);
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    await showExportSheet(context, text: text, filename: 'aevora_chat_$stamp.txt');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: Column(
        children: [
          _topBar(),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) => _MessageBubble(
                message: _messages[index],
                playingId: _playingId,
                onSpeak: (id, rate) =>
                    _speak(_messages[index].text, messageId: id, rate: rate),
                onStop: _stopPlayback,
              ),
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
          _inputBar(),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      color: const Color(0xFF0D1424),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: _green, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('ايفورا — محادثة',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 2),
                Text('يعمل بالكامل داخل متصفحك · البيانات محفوظة محلياً',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            onPressed: _exportChat,
            tooltip: 'تصدير المحادثة مع ترويج ايفورا',
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white70),
          ),
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
              textDirection: TextDirection.rtl,
              style: const TextStyle(color: Colors.white, height: 1.5),
              keyboardType: TextInputType.multiline,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
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
            onPressed: _isLoading ? null : _openPlainTextPaste,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF2A2F45),
            ),
            icon: const Icon(Icons.content_paste_go_rounded, color: Colors.white),
            tooltip: 'لصق نص من Word',
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

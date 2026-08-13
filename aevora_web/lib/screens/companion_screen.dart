import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import '../api.dart';
import '../config.dart';
import '../widgets/plain_text_paste_dialog.dart';

class CompanionScreen extends StatefulWidget {
  final KeySettings keys;
  const CompanionScreen({super.key, required this.keys});

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _Msg {
  final String id;
  String text;
  final bool isUser;
  _Msg(this.text, this.isUser)
      : id = '${DateTime.now().microsecondsSinceEpoch}_${text.hashCode}';
}

class _CompanionScreenState extends State<CompanionScreen> {
  static const _green = Color(0xFF4CAF50);
  static const _bg = Color(0xFF070B14);
  static const _card = Color(0xFF141A2A);

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Msg> _messages = [];
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<String?> _playingId = ValueNotifier<String?>(null);

  bool _loading = true;
  bool _sending = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _audioUnlocked = false;
  String _error = '';

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
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isSpeaking = false);
        _playingId.value = null;
      }
    });
    _refresh();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _recorder.dispose();
    _player.dispose();
    _playingId.dispose();
    super.dispose();
  }

  Future<void> _unlockAudio() async {
    if (_audioUnlocked) return;
    try {
      await _player.stop();
      await _player.play(BytesSource(_silentWav()));
      _audioUnlocked = true;
    } catch (_) {}
  }

  Uint8List _silentWav() {
    const sampleRate = 8000;
    const dataLen = 800;
    final b = BytesBuilder();
    b.add([0x52, 0x49, 0x46, 0x46]);
    b.add(_le32(36 + dataLen));
    b.add([0x57, 0x41, 0x56, 0x45]);
    b.add([0x66, 0x6d, 0x74, 0x20]);
    b.add(_le32(16));
    b.add(_le16(1));
    b.add(_le16(1));
    b.add(_le32(sampleRate));
    b.add(_le32(sampleRate));
    b.add(_le16(1));
    b.add(_le16(8));
    b.add([0x64, 0x61, 0x74, 0x61]);
    b.add(_le32(dataLen));
    b.add(Uint8List(dataLen));
    return b.toBytes();
  }

  List<int> _le32(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
  List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];

  Future<void> _refresh() async {
    try {
      final s = await companionState(widget.keys);
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

        // لا تُظهر المبادرة إذا أُغلقت يدوياً في هذه الجلسة
        if (!_proactiveDismissed) {
          _proactive = s['proactive'] as String?;
          _suggestedPrompt = s['suggested_prompt'] as String?;
        }

        final recent = s['recent'] as List? ?? [];
        if (recent.isEmpty) {
          _messages
            ..clear()
            ..add(_Msg(
                'أنا هنا دائماً 👋 صديقك الذي يتذكر كل شيء.\n'
                'احكِ لي عن يومك، وسأصحح لغتك الإنجليزية، وأذكّرك بمهامك، '
                'وأتعرف عليك يوماً بعد يوم.',
                false));
        } else {
          _messages.clear();
          for (final m in recent.cast<Map<String, dynamic>>()) {
            final role = m['role'] as String? ?? '';
            final text = (m['text'] as String? ?? '').trim();
            if (text.isEmpty) continue;
            _messages.add(_Msg(text, role == 'user'));
          }
        }
        _loading = false;
        _error = '';
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر الاتصال بالمساعد: $e';
      });
    }
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
    final clean = text.trim();
    if (clean.isEmpty || _sending) return;
    await _unlockAudio();
    setState(() {
      _messages.add(_Msg(clean, true));
      _sending = true;
      _input.clear();
      _proactive = null;
      _suggestedPrompt = null;
      _proactiveDismissed = true;
    });
    _scrollToBottom();

    final assistant = _Msg('', false);
    setState(() => _messages.add(assistant));

    try {
      final reply = await streamCompanion(
        clean,
        widget.keys,
        onChunk: (partial) {
          assistant.text += partial;
          if (mounted) setState(() {});
          _scrollToBottom();
        },
      );
      assistant.text = reply;
      if (mounted) setState(() {});
      _scrollToBottom();
      // تشغيل صوتي تلقائي بعد الرد
      await _speak(reply, messageId: assistant.id);
    } catch (e) {
      assistant.text = 'خطأ: $e';
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _sending = false);
      // تحديث المهام/الذاكرة بعد التحليل، والمبادرة محمية بواسطة _proactiveDismissed
      await _refresh();
    }
  }

  Future<void> _speak(String text, {required String messageId, String? rate}) async {
    if (text.isEmpty) return;
    try {
      if (_playingId.value == messageId) {
        await _player.stop();
        _playingId.value = null;
        if (mounted) setState(() => _isSpeaking = false);
        return;
      }
      await _player.stop();
      _playingId.value = messageId;
      if (mounted) setState(() => _isSpeaking = true);
      final url =
          '$apiBaseUrl/voice/synthesize?text=${Uri.encodeComponent(text)}&voice=ar-SA-HamedNeural&rate=${Uri.encodeComponent(rate ?? '+0%')}&pitch=+0%25';
      final res = await http.post(Uri.parse(url), headers: authHeaders(widget.keys));
      if (res.statusCode == 200) {
        await _player.play(BytesSource(res.bodyBytes));
      } else {
        _playingId.value = null;
        if (mounted) setState(() => _isSpeaking = false);
      }
    } catch (_) {
      _playingId.value = null;
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _toggleVoice() async {
    await _unlockAudio();
    if (_isSpeaking) {
      await _player.stop();
      _playingId.value = null;
      if (mounted) setState(() => _isSpeaking = false);
    }
    if (_isListening) {
      await _stopAndTranscribe();
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        _addError('تم رفض إذن الميكروفون.');
        return;
      }
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000),
        path: 'evora_companion_voice.wav',
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

      if (mounted) setState(() => _sending = true);
      final audioBytes = (await http.get(Uri.parse(path))).bodyBytes;

      final uploadReq = http.MultipartRequest(
        'POST',
        Uri.parse('$apiBaseUrl/voice/transcribe'),
      );
      uploadReq.headers.addAll(authHeaders(widget.keys));
      uploadReq.files.add(http.MultipartFile.fromBytes(
        'file',
        audioBytes,
        filename: 'companion_voice.wav',
      ));
      final res = await uploadReq.send().timeout(const Duration(minutes: 2));
      final body = await res.stream.bytesToString();
      if (res.statusCode != 200) {
        throw Exception('التعرف على الصوت فشل (${res.statusCode}): $body');
      }
      final text = (jsonDecode(body)['text'] ?? '').toString().trim();
      if (text.isEmpty) {
        _addError('لم يُفهم الكلام. حاول مرة أخرى.');
        if (mounted) setState(() => _sending = false);
        return;
      }
      if (mounted) setState(() => _sending = false);
      await _send(text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _isListening = false;
        });
      }
      _addError('خطأ في الصوت: $e');
    }
  }

  void _addError(String msg) {
    if (!mounted) return;
    setState(() => _messages.add(_Msg(msg, false)));
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

  Future<void> _dismissProactive() async {
    setState(() {
      _proactive = null;
      _suggestedPrompt = null;
      _proactiveDismissed = true;
    });
    try {
      await companionAcknowledge(widget.keys);
    } catch (_) {}
  }

  Future<void> _toggleTask(Map<String, dynamic> task) async {
    try {
      await companionToggleTask(widget.keys, task['id'] as String);
    } catch (_) {}
    await _refresh();
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    try {
      await companionDeleteTask(widget.keys, task['id'] as String);
    } catch (_) {}
    await _refresh();
  }

  Future<void> _addTask() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('أضف مهمة تذكّرني بها',
            style: TextStyle(color: Colors.white)),
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
        await companionAddTask(widget.keys, text);
      } catch (_) {}
      await _refresh();
    }
  }

  Future<void> _resetMemory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('مسح ذاكرة المساعد؟',
            style: TextStyle(color: Colors.white)),
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
        await companionReset(widget.keys);
      } catch (_) {}
      _proactiveDismissed = false;
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _header(),
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: _green)),
            )
          else if (_error.isNotEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70)),
                ),
              ),
            )
          else ...[
            if (_proactive != null && !_proactiveDismissed) _proactiveCard(),
            Expanded(child: _chatList()),
            _inputBar(),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      color: const Color(0xFF0D1422),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFF1D3A1D),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.psychology_alt_rounded, color: _green, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('المساعد الشخصي',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(_buildSubtitle(),
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          _clickableChip(
            Icons.memory_rounded,
            'ذاكرة: ${_memories.length}',
            active: !_hideMemoryPanel,
            onTap: () => setState(() => _hideMemoryPanel = !_hideMemoryPanel),
          ),
          const SizedBox(width: 8),
          _clickableChip(
            Icons.task_alt_rounded,
            'مهام: $_taskCount',
            active: !_hideTasksPanel,
            onTap: () => setState(() => _hideTasksPanel = !_hideTasksPanel),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _resetMemory,
            tooltip: 'مسح الذاكرة',
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white38, size: 20),
          ),
        ],
      ),
    );
  }

  String _buildSubtitle() {
    final parts = <String>[];
    if (_name != null && _name!.isNotEmpty) parts.add(_name!);
    if (_level != null && _level!.isNotEmpty) parts.add(_level!);
    if (parts.isEmpty) return 'صديقك الدائم الذي يتذكر كل شيء';
    return parts.join(' · ');
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
        gradient: const LinearGradient(colors: [Color(0xFF1D3A1D), Color(0xFF14292A)]),
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
                    style: TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              GestureDetector(
                onTap: _dismissProactive,
                child: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
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
                onPressed: _sending ? null : () {
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

  Widget _chatList() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_hasExtraPanels() ? 1 : 0),
      itemBuilder: (context, index) {
        if (_hasExtraPanels() && index == _messages.length) return _infoPanels();
        final m = _messages[index];
        return _Bubble(
          message: m,
          playingId: _playingId,
          onSpeak: (id, rate) => _speak(m.text, messageId: id, rate: rate),
          onStop: () async {
            await _player.stop();
            _playingId.value = null;
            if (mounted) setState(() => _isSpeaking = false);
          },
        );
      },
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
        child: const Icon(Icons.add_circle_outline_rounded, color: _green, size: 20),
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
                style: TextStyle(color: Colors.white, fontSize: 13,
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
              child: Text(item, style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _green, size: 17),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
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
                    child: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
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
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              textDirection: TextDirection.rtl,
              style: const TextStyle(color: Colors.white),
              onSubmitted: _send,
              decoration: InputDecoration(
                hintText: 'اكتب لصديقك...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF141A2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sending ? null : _openPlainTextPaste,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF2A2F45),
            ),
            icon: const Icon(Icons.content_paste_go_rounded, color: Colors.white),
            tooltip: 'لصق نص من Word',
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sending ? null : _toggleVoice,
            style: IconButton.styleFrom(
              backgroundColor: _isListening
                  ? Colors.redAccent
                  : _sending
                      ? Colors.amber
                      : const Color(0xFF1D3A1D),
            ),
            icon: Icon(
              _isListening ? Icons.stop_circle_rounded : Icons.mic_none,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sending ? null : () => _send(_input.text),
            style: IconButton.styleFrom(backgroundColor: _green),
            icon: const Icon(Icons.send_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatefulWidget {
  final _Msg message;
  final ValueNotifier<String?> playingId;
  final Future<void> Function(String id, String? rate) onSpeak;
  final Future<void> Function() onStop;

  const _Bubble({
    required this.message,
    required this.playingId,
    required this.onSpeak,
    required this.onStop,
  });

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
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
      setState(() { _playingNormal = false; _playingSlow = false; });
      await widget.onStop();
      return;
    }
    setState(() {
      if (slow) { _playingSlow = true; _playingNormal = false; }
      else { _playingNormal = true; _playingSlow = false; }
    });
    await widget.onSpeak(widget.message.id, slow ? '-25%' : '+0%');
    if (mounted) setState(() { _playingNormal = false; _playingSlow = false; });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: m.isUser ? Alignment.centerLeft : Alignment.centerRight,
        child: Column(
          crossAxisAlignment: m.isUser ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: BoxDecoration(
                color: m.isUser ? const Color(0xFF1D3A1D) : const Color(0xFF141A2A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(m.text, textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white, height: 1.6, fontSize: 15)),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(
                  icon: _playingNormal
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
                      : Icon(_isPlaying ? Icons.stop_rounded : Icons.volume_up_rounded,
                          size: 16, color: _isPlaying ? _green : Colors.white54),
                  onPressed: () => _play(),
                  tooltip: 'استماع',
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: _playingSlow
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
                      : const Icon(Icons.speed_rounded, size: 16, color: Colors.white54),
                  onPressed: () => _play(slow: true),
                  tooltip: 'استماع ببطء',
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icon(_copied ? Icons.check_rounded : Icons.content_copy_rounded,
                      size: 16, color: _copied ? _green : Colors.white54),
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

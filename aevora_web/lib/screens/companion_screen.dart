import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../config.dart';

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

  bool _loading = true;
  bool _sending = false;
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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

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
        _proactive = s['proactive'] as String?;
        _suggestedPrompt = s['suggested_prompt'] as String?;

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
    setState(() {
      _messages.add(_Msg(clean, true));
      _sending = true;
      _input.clear();
      _proactive = null;
      _suggestedPrompt = null;
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
    } catch (e) {
      assistant.text = 'خطأ: $e';
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _sending = false);
      await _refresh();
    }
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
              child: Center(
                child: CircularProgressIndicator(color: _green),
              ),
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
            if (_proactive != null) _proactiveCard(),
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
            child: const Icon(Icons.psychology_alt_rounded,
                color: _green, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('المساعد الشخصي',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  _buildSubtitle(),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          _statChip(Icons.memory_rounded, 'ذاكرة: ${_memories.length}'),
          const SizedBox(width: 8),
          _statChip(Icons.task_alt_rounded, 'مهام: $_taskCount'),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _resetMemory,
            tooltip: 'مسح الذاكرة',
            icon: const Icon(Icons.delete_sweep_outlined,
                color: Colors.white38, size: 20),
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

  Widget _statChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: _green, size: 13),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _proactiveCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D3A1D), Color(0xFF14292A)],
        ),
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
              const Text('لحظة من ايفورا',
                  style: TextStyle(
                      color: _green, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(_proactive ?? '',
              style: const TextStyle(color: Colors.white, height: 1.5)),
          if (_suggestedPrompt != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _sending ? null : () => _send(_suggestedPrompt!),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.auto_awesome_rounded,
                    color: _green, size: 16),
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
        if (_hasExtraPanels() && index == _messages.length) {
          return _infoPanels();
        }
        final m = _messages[index];
        return _Bubble(message: m);
      },
    );
  }

  bool _hasExtraPanels() {
    return _tasks.isNotEmpty ||
        _memories.isNotEmpty ||
        _goals.isNotEmpty ||
        _vocab.isNotEmpty ||
        _corrections.isNotEmpty;
  }

  Widget _infoPanels() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_tasks.isNotEmpty) ...[
          _tasksPanel(),
          const SizedBox(height: 10),
        ],
        if (_memories.isNotEmpty || _goals.isNotEmpty ||
            _vocab.isNotEmpty || _corrections.isNotEmpty) ...[
          _memoryPanel(),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _tasksPanel() {
    return _panelCard(
      icon: Icons.task_alt_rounded,
      title: 'مهامك',
      child: Column(
        children: [
          for (final t in _tasks) _taskRow(t),
        ],
      ),
    );
  }

  Widget _taskRow(Map<String, dynamic> t) {
    final done = t['completed'] == true;
    return Row(
      children: [
        Checkbox(
          value: done,
          activeColor: _green,
          onChanged: (_) => _toggleTask(t),
        ),
        Expanded(
          child: InkWell(
            onTap: () => _toggleTask(t),
            child: Text(
              t['text'] as String? ?? '',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: Colors.white38,
              ),
            ),
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
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _green, size: 17),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              InkWell(
                onTap: _addTask,
                child: const Icon(Icons.add_circle_outline_rounded,
                    color: _green, size: 20),
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
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              ),
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

class _Bubble extends StatelessWidget {
  final _Msg message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final m = message;
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
                color: m.isUser
                    ? const Color(0xFF1D3A1D)
                    : const Color(0xFF141A2A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                m.text,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, height: 1.6, fontSize: 15),
              ),
            ),
            const SizedBox(height: 4),
            if (!m.isUser)
              GestureDetector(
                onTap: () =>
                    Clipboard.setData(ClipboardData(text: m.text)),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.content_copy_rounded,
                          size: 14, color: Colors.white38),
                      SizedBox(width: 4),
                      Text('نسخ',
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

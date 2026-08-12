import 'package:flutter/material.dart';

import '../api.dart';
import '../config.dart';

class MemoryScreen extends StatefulWidget {
  final KeySettings keys;
  const MemoryScreen({super.key, required this.keys});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  static const _green = Color(0xFF4CAF50);
  static const _bg = Color(0xFF070B14);
  static const _card = Color(0xFF141A2A);

  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await companionMemory(widget.keys);
      if (!mounted) return;
      setState(() => _data = d);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'تعذر جلب الذاكرة: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('ذاكرة المساعد'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _green));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    final profile = (_data?['profile'] as Map<String, dynamic>?) ?? {};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _identityCard(profile),
        const SizedBox(height: 12),
        if (profile['goals'] is List && (profile['goals'] as List).isNotEmpty)
          _section(
            icon: Icons.flag_rounded,
            title: 'أهدافك (${(profile['goals'] as List).length})',
            chips: (profile['goals'] as List).cast<String>(),
          ),
        if (profile['interests'] is List && (profile['interests'] as List).isNotEmpty)
          _section(
            icon: Icons.favorite_rounded,
            title: 'اهتماماتك (${(profile['interests'] as List).length})',
            chips: (profile['interests'] as List).cast<String>(),
          ),
        if (_data?['memories'] is List && (_data!['memories'] as List).isNotEmpty)
          _bulleted(
            icon: Icons.psychology_rounded,
            title: 'ذكرياتك وحقائقك (${(_data!['memories'] as List).length})',
            items: (_data!['memories'] as List).cast<String>(),
          ),
        if (profile['vocabulary'] is List && (profile['vocabulary'] as List).isNotEmpty)
          _bulleted(
            icon: Icons.menu_book_rounded,
            title: 'المفردات التي علّمها لك (${(profile['vocabulary'] as List).length})',
            items: (profile['vocabulary'] as List).cast<String>(),
          ),
        if (profile['last_corrections'] is List &&
            (profile['last_corrections'] as List).isNotEmpty)
          _bulleted(
            icon: Icons.edit_note_rounded,
            title: 'آخر تصحيحات لغتك (${(profile['last_corrections'] as List).length})',
            items: (profile['last_corrections'] as List).cast<String>(),
          ),
        if (profile['learning_stats'] is Map &&
            (profile['learning_stats'] as Map).isNotEmpty)
          _statsCard(profile['learning_stats'] as Map<String, dynamic>),
        if (_data?['tasks'] is List && (_data!['tasks'] as List).isNotEmpty)
          _tasksCard((_data!['tasks'] as List).cast<Map<String, dynamic>>()),
        if (_data?['summary'] != null &&
            (_data!['summary'] as String).toString().trim().isNotEmpty)
          _textCard(
            icon: Icons.summarize_rounded,
            title: 'ملخص المحادثات السابقة',
            body: _data!['summary'] as String,
          ),
        if (_data?['history'] is List && (_data!['history'] as List).isNotEmpty)
          _historyCard((_data!['history'] as List).cast<Map<String, dynamic>>()),
        const SizedBox(height: 12),
        const Text(
          'كل هذه المعلومات تُستعمل أثناء محادثتك: اذكر مثلاً «ابحث عن خيوط طباعة تناسب طابعتتي» '
          'وسيتذكر المساعد تفاصيل حديثكما السابق (مثل اسم طابعتك) ويهيّئ الرد بناءً عليها.',
          style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.7),
        ),
      ],
    );
  }

  Widget _identityCard(Map<String, dynamic> profile) {
    final rows = <Widget>[];
    final name = profile['name'] as String?;
    final level = profile['english_level'] as String?;
    if (name != null && name.isNotEmpty) {
      rows.add(_kv('اسمك', name));
    }
    if (level != null && level.isNotEmpty) {
      rows.add(_kv('مستواك في الإنجليزية', level));
    }
    if (rows.isEmpty) {
      rows.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('لا يعرف اسمك بعد — تحدث معه في المحادثة وسيحفظه.',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
      ));
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1D3A1D), Color(0xFF14292A)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.badge_rounded, color: _green, size: 18),
            SizedBox(width: 6),
            Text('من يعرفك المساعد أنه',
                style: TextStyle(color: _green, fontWeight: FontWeight.bold, fontSize: 14)),
          ]),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$k: ', style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Expanded(
            child: Text(v, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required List<String> chips,
  }) {
    return _panelCard(
      title: title,
      icon: icon,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in chips)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _green.withValues(alpha: 0.25)),
              ),
              child: Text(c, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _bulleted({required IconData icon, required String title, required List<String> items}) {
    return _panelCard(
      title: title,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: _green)),
                  Expanded(
                    child: Text(item,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statsCard(Map<String, dynamic> stats) {
    final rows = <Widget>[];
    stats.forEach((k, v) {
      rows.add(_kv(k, '$v'));
    });
    return _panelCard(icon: Icons.query_stats_rounded, title: 'إحصائيات التعلم', child: Column(children: rows));
  }

  Widget _tasksCard(List<Map<String, dynamic>> tasks) {
    return _panelCard(
      icon: Icons.task_alt_rounded,
      title: 'مهامك (${tasks.length})',
      child: Column(
        children: [
          for (final t in tasks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    t['completed'] == true
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: t['completed'] == true ? _green : Colors.white38,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(t['text'] as String? ?? '',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            decoration: t['completed'] == true
                                ? TextDecoration.lineThrough
                                : null)),
                  ),
                  if (t['due'] != null)
                    Text('${t['due']}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _textCard({required IconData icon, required String title, required String body}) {
    return _panelCard(
      icon: icon,
      title: title,
      child: Text(body, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.7)),
    );
  }

  Widget _historyCard(List<Map<String, dynamic>> history) {
    final reversed = history.reversed.toList();
    return _panelCard(
      icon: Icons.chat_bubble_rounded,
      title: 'سجل المحادثة (${history.length})',
      child: Column(
        children: [
          for (final m in reversed) _historyRow(m),
        ],
      ),
    );
  }

  Widget _historyRow(Map<String, dynamic> m) {
    final isUser = m['role'] == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: isUser ? const Color(0xFF1D3A1D) : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(isUser ? 'أنت' : 'ايفورا',
                style: TextStyle(color: isUser ? _green : Colors.white70, fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(m['text'] as String? ?? '',
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6)),
          ),
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: _green, size: 18),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

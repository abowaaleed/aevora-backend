import 'package:flutter/material.dart';

import '../client/client_reminders.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  static const _green = Color(0xFF4CAF50);
  bool _loading = true;
  ReminderPrefs _prefs = const ReminderPrefs();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await ReminderService.instance.load();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await ReminderService.instance.saveAndApply(_prefs);
  }

  void _add(ReminderType type) {
    setState(() {
      _prefs = _prefs.copyWith(items: [
        ..._prefs.items,
        ReminderItem(id: ReminderItem.generateId(), type: type),
      ]);
    });
    _save();
  }

  void _remove(String id) {
    setState(() => _prefs = _prefs.copyWith(
        items: _prefs.items.where((r) => r.id != id).toList()));
    _save();
  }

  void _update(String id, ReminderItem Function(ReminderItem) fn) {
    setState(() => _prefs = _prefs.copyWith(
        items: _prefs.items.map((r) => r.id == id ? fn(r) : r).toList()));
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(
        title: const Text('رسائل ايفورا الذكية'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const Text(
                  'اختر الفكرة أو المهمة، اكتب ما تريد، ثم حدّد الأيام والساعة. ايفورا تذكّرك وتفتح النقاش معك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, height: 1.5),
                ),
                const SizedBox(height: 22),
                _sectionTitle('أفكار وسلوكيات'),
                const SizedBox(height: 8),
                if (_prefs.ideas.isEmpty)
                  _emptyHint('لا توجد أفكار بعد — اضغط إضافة فكرة.'),
                for (final item in _prefs.ideas) _card(item, isIdea: true),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _add(ReminderType.idea),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة فكرة أخرى'),
                  style: FilledButton.styleFrom(backgroundColor: _green),
                ),
                const SizedBox(height: 28),
                _sectionTitle('المهام'),
                const SizedBox(height: 8),
                const Text(
                  'إذا قلت في الدردشة: «ذكرني بموعد الساعة 10 مساءً» تُضاف المهمة هنا تلقائياً مع الوقت.',
                  style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 8),
                if (_prefs.tasks.isEmpty)
                  _emptyHint('لا توجد مهام بعد — اكتب مهمة أو اطلبها من الدردشة.'),
                for (final item in _prefs.tasks) _card(item, isIdea: false),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _add(ReminderType.task),
                  icon: const Icon(Icons.add_task),
                  label: const Text('إضافة مهمة أخرى'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String t) => Text(
        t,
        style: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      );

  Widget _emptyHint(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(color: Colors.white38)),
      );

  Widget _card(ReminderItem item, {required bool isIdea}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isIdea
                ? 'اكتب أي موضوع تريد ممارسته معي'
                : 'اكتب ما هي المهمة',
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('txt_${item.id}'),
            initialValue: isIdea
                ? (item.interests.isNotEmpty ? item.interests : item.title)
                : item.title,
            minLines: 2,
            maxLines: 4,
            textDirection: TextDirection.rtl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: isIdea
                  ? 'مثال: قصص ملهمة عن الذكاء الاصطناعي'
                  : 'مثال: موعد زيارة الطبيب',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => _update(item.id, (r) => isIdea
                ? r.copyWith(interests: v.trim(), title: r.title)
                : r.copyWith(title: v.trim())),
          ),
          const SizedBox(height: 12),
          const Text('الأيام والوقت',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip('يومياً', item.days.length == 7, () {
                _update(item.id, (r) => r.copyWith(
                    days: r.days.length == 7 ? const [0] : const [0, 1, 2, 3, 4, 5, 6]));
              }),
              for (var i = 0; i < 7; i++)
                _chip(['سبت', 'أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة'][i],
                    item.days.contains(i), () {
                  _update(item.id, (r) {
                    final d = List<int>.from(r.days);
                    if (d.contains(i)) {
                      d.remove(i);
                    } else {
                      d.add(i);
                    }
                    return r.copyWith(days: d);
                  });
                }),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: item.hour, minute: item.minute),
                    );
                    if (t != null) {
                      _update(item.id, (r) => r.copyWith(hour: t.hour, minute: t.minute));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'الساعة ${item.timeLabel}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _remove(item.id),
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _green.withValues(alpha: 0.2) : Colors.white10,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _green : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _green : Colors.white54,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

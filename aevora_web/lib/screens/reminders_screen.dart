import 'package:flutter/material.dart';

import '../client/client_reminders.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  ReminderPrefs _prefs = const ReminderPrefs();
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await ReminderService.instance.load();
    if (mounted) setState(() { _prefs = p; _loading = false; });
  }

  Future<void> _save() async {
    await ReminderService.instance.saveAndApply(_prefs);
  }

  void _removeReminder(String id) {
    setState(() => _prefs = _prefs.copyWith(
        items: _prefs.items.where((r) => r.id != id).toList()));
    _save();
  }

  void _updateReminder(String id, ReminderItem Function(ReminderItem) updater) {
    setState(() => _prefs = _prefs.copyWith(
        items: _prefs.items.map((r) => r.id == id ? updater(r) : r).toList()));
    _save();
  }

  Future<void> _testNotification(ReminderType type) async {
    await ReminderService.instance.testNotification(type);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أُرسل تنبيه اختباري — تحقق من شريط الإشعارات.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(
        title: const Text('تنبيهات ايفورا'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF4CAF50),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'أفكار وسلوكيات'),
            Tab(text: 'مهام'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildList(ReminderType.idea),
                _buildList(ReminderType.task),
              ],
            ),
    );
  }

  Widget _buildList(ReminderType type) {
    final items = type == ReminderType.idea ? _prefs.ideas : _prefs.tasks;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          type == ReminderType.idea
              ? 'أفكار وسلوكيات يومية تساعدك على التعلّم المستمر.'
              : 'تذكير بمهامك اليومية والactive learning.',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _buildPreviewCard(type),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                type == ReminderType.idea
                    ? 'لم تُضف أي فكرة بعد.'
                    : 'لم تُضف أي مهمة بعد.',
                style: const TextStyle(color: Colors.white38),
              ),
            ),
          )
        else
          ...items.map((item) => _buildReminderCard(item)),
        const SizedBox(height: 16),
        _buildAddButton(type),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _testNotification(type),
            icon: const Icon(Icons.send, size: 18),
            label: Text(type == ReminderType.idea
                ? 'اختبار تنبيه أفكار'
                : 'اختبار تنبيه مهام'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF81C784),
              side: const BorderSide(color: Color(0xFF81C784)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewCard(ReminderType type) {
    final content = DailyContent.previewForType(type: type);
    final isIdea = type == ReminderType.idea;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF141A2A),
            isIdea ? const Color(0xFF1A2740) : const Color(0xFF1A2A1A),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isIdea
              ? const Color(0xFF2196F3).withValues(alpha: 0.3)
              : const Color(0xFF4CAF50).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isIdea ? Icons.lightbulb : Icons.check_circle_outline,
                color: isIdea ? const Color(0xFF2196F3) : const Color(0xFF4CAF50),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isIdea ? 'معاينة تنبيه الأفكار' : 'معاينة تنبيه المهام',
                style: TextStyle(
                  color: isIdea ? const Color(0xFF64B5F6) : const Color(0xFF81C784),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isIdea ? 'ايفورا 💡' : 'ايفورا ✅',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderCard(ReminderItem item) {
    final isIdea = item.type == ReminderType.idea;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1828),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.enabled
              ? (isIdea ? const Color(0xFF2196F3).withValues(alpha: 0.4) : const Color(0xFF4CAF50).withValues(alpha: 0.4))
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isIdea ? Icons.lightbulb_outline : Icons.task_alt,
                color: item.enabled
                    ? (isIdea ? const Color(0xFF2196F3) : const Color(0xFF4CAF50))
                    : Colors.white24,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title.isEmpty ? (isIdea ? 'فكرة / سلوك' : 'مهمة') : item.title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: item.enabled ? 0.9 : 0.4),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch(
                value: item.enabled,
                onChanged: (v) => _updateReminder(item.id, (r) => r.copyWith(enabled: v)),
                activeThumbColor: const Color(0xFF4CAF50),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 20),
                onPressed: () => _removeReminder(item.id),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _pickTime(item),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time, color: Color(0xFF81C784), size: 16),
                  const SizedBox(width: 6),
                  Text(item.timeLabel, style: const TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.w600, fontSize: 14)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _pickDays(item),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today, color: Color(0xFF64B5F6), size: 14),
                  const SizedBox(width: 6),
                  Text(item.daysLabel, style: const TextStyle(color: Color(0xFF64B5F6), fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(ReminderType type) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _showAddSheet(type),
        icon: const Icon(Icons.add, size: 20),
        label: Text(type == ReminderType.idea ? 'إضافة فكرة / سلوك' : 'إضافة مهمة'),
        style: ElevatedButton.styleFrom(
          backgroundColor: type == ReminderType.idea ? const Color(0xFF1565C0) : const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  void _showAddSheet(ReminderType type) {
    final titleCtrl = TextEditingController();
    int hour = 9;
    int minute = 0;
    List<int> days = [0, 1, 2, 3, 4, 5, 6];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C1828),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  type == ReminderType.idea ? 'إضافة فكرة / سلوك' : 'إضافة مهمة',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: type == ReminderType.idea
                        ? 'مثال: اقرأ فقرة إنجليزية يومياً'
                        : 'مثال: راجع مفردات اليوم',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.07),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 16),
                const Text('الوقت', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: hour, minute: minute));
                    if (t != null) setSheetState(() { hour = t.hour; minute = t.minute; });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, color: Color(0xFF81C784)),
                        const SizedBox(width: 8),
                        Text('${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('الأيام', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _buildDayChipsRow1(days, setSheetState),
                const SizedBox(height: 6),
                _buildDayChipsRow2(days, setSheetState),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (days.isEmpty) days = [0, 1, 2, 3, 4, 5, 6];
                      final newItem = ReminderItem(
                        id: ReminderItem.generateId(),
                        type: type,
                        title: titleCtrl.text.trim(),
                        hour: hour,
                        minute: minute,
                        days: days,
                      );
                      setState(() => _prefs = _prefs.copyWith(items: [..._prefs.items, newItem]));
                      _save();
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: type == ReminderType.idea ? const Color(0xFF1565C0) : const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('حفظ التنبيه', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayChipsRow1(List<int> days, StateSetter setSheetState) {
    return Row(
      children: [
        _dayChip('كل', days.length == 7, () {
          setSheetState(() => days = days.length == 7 ? [] : [0, 1, 2, 3, 4, 5, 6]);
        }),
        const SizedBox(width: 6),
        _dayChip('سبت', days.contains(0), () {
          setSheetState(() { if (days.contains(0)) days = days.where((d) => d != 0).toList(); else days = [...days, 0]; });
        }),
        _dayChip('أحد', days.contains(1), () {
          setSheetState(() { if (days.contains(1)) days = days.where((d) => d != 1).toList(); else days = [...days, 1]; });
        }),
        _dayChip('اثنين', days.contains(2), () {
          setSheetState(() { if (days.contains(2)) days = days.where((d) => d != 2).toList(); else days = [...days, 2]; });
        }),
      ],
    );
  }

  Widget _buildDayChipsRow2(List<int> days, StateSetter setSheetState) {
    return Row(
      children: [
        _dayChip('ثلاثاء', days.contains(3), () {
          setSheetState(() { if (days.contains(3)) days = days.where((d) => d != 3).toList(); else days = [...days, 3]; });
        }),
        const SizedBox(width: 6),
        _dayChip('أربعاء', days.contains(4), () {
          setSheetState(() { if (days.contains(4)) days = days.where((d) => d != 4).toList(); else days = [...days, 4]; });
        }),
        const SizedBox(width: 6),
        _dayChip('خميس', days.contains(5), () {
          setSheetState(() { if (days.contains(5)) days = days.where((d) => d != 5).toList(); else days = [...days, 5]; });
        }),
        const SizedBox(width: 6),
        _dayChip('جمعة', days.contains(6), () {
          setSheetState(() { if (days.contains(6)) days = days.where((d) => d != 6).toList(); else days = [...days, 6]; });
        }),
      ],
    );
  }

  Widget _dayChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4CAF50).withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF4CAF50).withValues(alpha: 0.6) : Colors.white12,
          ),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? const Color(0xFF81C784) : Colors.white54,
          fontSize: 11, fontWeight: FontWeight.w600,
        )),
      ),
    );
  }

  Future<void> _pickTime(ReminderItem item) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: item.hour, minute: item.minute),
    );
    if (t != null) {
      _updateReminder(item.id, (r) => r.copyWith(hour: t.hour, minute: t.minute));
    }
  }

  void _pickDays(ReminderItem item) {
    final selected = List<int>.from(item.days);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0C1828),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          const dayNames = ['سبت', 'أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة'];
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('اختيار الأيام', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 16)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _dayChip('كل يوم', selected.length == 7, () {
                      setSheetState(() => selected.length == 7 ? selected.clear() : selected.addAll([0, 1, 2, 3, 4, 5, 6]));
                    }),
                    for (int i = 0; i < 7; i++)
                      _dayChip(dayNames[i], selected.contains(i), () {
                        setSheetState(() {
                          if (selected.contains(i)) selected.remove(i);
                          else selected.add(i);
                        });
                      }),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      _updateReminder(item.id, (r) => r.copyWith(
                          days: selected.isEmpty ? [0, 1, 2, 3, 4, 5, 6] : selected));
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('حفظ'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

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
    if (mounted) {
      setState(() {
        _prefs = p;
        _loading = false;
      });
    }
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

  Future<void> _testNotification(ReminderType type, {String interests = ''}) async {
    await ReminderService.instance.testNotification(type, interests: interests);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أُرسل تنبيه اختباري بنغمة ايفورا المميزة 🎵'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(
        title: const Text(
          'تنبيهات ايفورا الذكية',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF070B14), Color(0xFF0C1220)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF4CAF50),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          tabs: const [
            Tab(text: 'أفكار وسلوكيات'),
            Tab(text: 'مهام يومية'),
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
    final isIdea = type == ReminderType.idea;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        _buildHeader(type),
        const SizedBox(height: 24),
        _buildPreviewSection(type),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isIdea ? 'تنبيهات الأفكار المجدولة' : 'قائمة المهام المجدولة',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            _buildSmallAddButton(type),
          ],
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          _buildEmptyState(type)
        else
          ...items.map((item) => _buildEnhancedReminderCard(item)),
        const SizedBox(height: 24),
        _buildActionButtons(type),
      ],
    );
  }

  Widget _buildHeader(ReminderType type) {
    final isIdea = type == ReminderType.idea;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isIdea
            ? const Color(0xFF1565C0).withValues(alpha: 0.1)
            : const Color(0xFF2E7D32).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isIdea
              ? const Color(0xFF1565C0).withValues(alpha: 0.2)
              : const Color(0xFF2E7D32).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isIdea ? const Color(0xFF1565C0) : const Color(0xFF2E7D32),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isIdea ? Icons.auto_awesome : Icons.assignment_turned_in,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isIdea ? 'نمو وتطوير مستمر' : 'إنجاز وتنظيم',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isIdea
                      ? 'سيقترح عليك الذكاء الاصطناعي أفكاراً وسلوكيات تناسب اهتماماتك.'
                      : 'حافظ على إنتاجيتك من خلال التذكيرات الدورية لمهامك الهامة.',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewSection(ReminderType type) {
    // We take the interests from the first enabled reminder of this type if exists
    final items = type == ReminderType.idea ? _prefs.ideas : _prefs.tasks;
    final firstWithInterests = items.firstWhere((element) => element.enabled && element.interests.isNotEmpty, orElse: () => items.isNotEmpty ? items.first : ReminderItem(id: '', type: type));
    
    final content = DailyContent.previewForType(type: type, interests: firstWithInterests.interests);
    final isIdea = type == ReminderType.idea;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'معاينة التنبيه القادم',
          style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isIdea
                  ? [const Color(0xFF2196F3), const Color(0xFF64B5F6)]
                  : [const Color(0xFF4CAF50), const Color(0xFF81C784)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1220),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset('assets/icons/app_icon.png', width: 24, height: 24, errorBuilder: (_, __, ___) => const Icon(Icons.notifications, color: Colors.blue, size: 24)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isIdea ? 'ايفورا • الآن' : 'ايفورا • الآن',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  isIdea ? 'ايفورا 💡' : 'ايفورا ✅',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ReminderType type) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.notifications_none, size: 64, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          Text(
            type == ReminderType.idea ? 'لا توجد أفكار مجدولة' : 'لا توجد مهام مجدولة',
            style: const TextStyle(color: Colors.white38, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedReminderCard(ReminderItem item) {
    final isIdea = item.type == ReminderType.idea;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141A2A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: item.enabled
              ? (isIdea ? const Color(0xFF2196F3).withValues(alpha: 0.3) : const Color(0xFF4CAF50).withValues(alpha: 0.3))
              : Colors.white.withValues(alpha: 0.05),
        ),
        boxShadow: item.enabled ? [
          BoxShadow(
            color: (isIdea ? const Color(0xFF2196F3) : const Color(0xFF4CAF50)).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: item.enabled
                          ? (isIdea ? const Color(0xFF2196F3).withValues(alpha: 0.1) : const Color(0xFF4CAF50).withValues(alpha: 0.1))
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isIdea ? Icons.lightbulb_outline : Icons.check_circle_outline,
                      color: item.enabled
                          ? (isIdea ? const Color(0xFF2196F3) : const Color(0xFF4CAF50))
                          : Colors.white24,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title.isEmpty ? (isIdea ? 'فكرة ذكية' : 'مهمة جديدة') : item.title,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: item.enabled ? 1.0 : 0.5),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (item.interests.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'الاهتمام: ${item.interests}',
                              style: TextStyle(color: (isIdea ? const Color(0xFF64B5F6) : const Color(0xFF81C784)).withValues(alpha: 0.7), fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: item.enabled,
                    onChanged: (v) => _updateReminder(item.id, (r) => r.copyWith(enabled: v)),
                    activeColor: const Color(0xFF4CAF50),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white.withValues(alpha: 0.02),
              child: Row(
                children: [
                  _buildCardAction(
                    icon: Icons.access_time,
                    label: item.timeLabel,
                    color: const Color(0xFF81C784),
                    onTap: () => _pickTime(item),
                  ),
                  const SizedBox(width: 12),
                  _buildCardAction(
                    icon: Icons.calendar_today,
                    label: item.daysLabel,
                    color: const Color(0xFF64B5F6),
                    onTap: () => _pickDays(item),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit_note, color: Colors.white38),
                    onPressed: () => _showAddSheet(item.type, existing: item),
                    tooltip: 'تعديل',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    onPressed: () => _removeReminder(item.id),
                    tooltip: 'حذف',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardAction({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallAddButton(ReminderType type) {
    return IconButton(
      onPressed: () => _showAddSheet(type),
      icon: const Icon(Icons.add_circle, color: Color(0xFF4CAF50), size: 28),
    );
  }

  Widget _buildActionButtons(ReminderType type) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _showAddSheet(type),
            icon: const Icon(Icons.add, size: 20),
            label: Text(type == ReminderType.idea ? 'إضافة تنبيه ذكي جديد' : 'إضافة مهمة جديدة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _testNotification(type),
            icon: const Icon(Icons.notifications_active_outlined, size: 20),
            label: const Text('إرسال تنبيه تجريبي الآن'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white12),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }

  void _showAddSheet(ReminderType type, {ReminderItem? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final interestCtrl = TextEditingController(text: existing?.interests ?? '');
    int hour = existing?.hour ?? 9;
    int minute = existing?.minute ?? 0;
    List<int> days = existing?.days ?? [0, 1, 2, 3, 4, 5, 6];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C1828),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48, height: 5,
                    decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  existing == null 
                      ? (type == ReminderType.idea ? 'ضبط تنبيه ذكي' : 'إضافة مهمة جديدة')
                      : 'تعديل التنبيه',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  type == ReminderType.idea
                      ? 'اكتب ما تريد أن يقترحه ايفورا في هذا الوقت، ثم اختر الأيام والساعة. عند التنبيه افتح التطبيق ليُسرد لك المحتوى.'
                      : 'اكتب المهمة والوقت. مثال: ذكرني بموعد الساعة العاشرة مساءً.',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 24),
                if (type == ReminderType.idea) ...[
                  const Text('ماذا تريد من ايفورا؟', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: interestCtrl,
                    minLines: 2,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'مثال: اقترح علي قصصاً ملهمة عن الذكاء الاصطناعي',
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 20),
                ],
                Text(type == ReminderType.task ? 'المهمة' : 'عنوان قصير (اختياري)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: titleCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: type == ReminderType.idea
                        ? 'مثال: قصة المساء'
                        : 'مثال: ذكرني بموعد الساعة العاشرة',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('وقت التنبيه', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
                              final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: hour, minute: minute));
                              if (t != null) setSheetState(() { hour = t.hour; minute = t.minute; });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.access_time, color: Color(0xFF81C784), size: 20),
                                  const SizedBox(width: 10),
                                  Text('${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
                                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('تكرار التنبيه', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _dayChip('يومياً', days.length == 7, () {
                      setSheetState(() => days = days.length == 7 ? [] : [0, 1, 2, 3, 4, 5, 6]);
                    }),
                    for (int i = 0; i < 7; i++)
                      _dayChip(['سبت', 'أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة'][i], days.contains(i), () {
                        setSheetState(() {
                          if (days.contains(i)) days = days.where((d) => d != i).toList();
                          else days = [...days, i];
                        });
                      }),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (days.isEmpty) days = [0, 1, 2, 3, 4, 5, 6];
                          if (existing != null) {
                            _updateReminder(existing.id, (r) => r.copyWith(
                              title: titleCtrl.text.trim(),
                              interests: interestCtrl.text.trim(),
                              hour: hour,
                              minute: minute,
                              days: days,
                            ));
                          } else {
                            final newItem = ReminderItem(
                              id: ReminderItem.generateId(),
                              type: type,
                              title: titleCtrl.text.trim(),
                              interests: interestCtrl.text.trim(),
                              hour: hour,
                              minute: minute,
                              days: days,
                            );
                            setState(() => _prefs = _prefs.copyWith(items: [..._prefs.items, newItem]));
                            _save();
                          }
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: Text(existing == null ? 'حفظ وتفعيل' : 'تحديث التنبيه', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4CAF50).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF4CAF50).withValues(alpha: 0.5) : Colors.white12,
          ),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? const Color(0xFF81C784) : Colors.white54,
          fontSize: 13, fontWeight: selected ? FontWeight.bold : FontWeight.normal,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          const dayNames = ['سبت', 'أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة'];
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('تكرار التنبيه', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _dayChip('يومياً', selected.length == 7, () {
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
                const SizedBox(height: 32),
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
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('تم', style: TextStyle(fontWeight: FontWeight.bold)),
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

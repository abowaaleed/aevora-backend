import 'package:flutter/material.dart';
import '../client/client_handoff.dart';
import '../client/client_reminders.dart';

class NotificationContentScreen extends StatefulWidget {
  final String? payload;

  const NotificationContentScreen({super.key, this.payload});

  @override
  State<NotificationContentScreen> createState() => _NotificationContentScreenState();
}

class _NotificationContentScreenState extends State<NotificationContentScreen> {
  ReminderItem? _reminder;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReminder();
  }

  Future<void> _loadReminder() async {
    if (widget.payload != null && widget.payload!.isNotEmpty) {
      if (widget.payload!.startsWith('test_')) {
         final type = widget.payload == 'test_task' ? ReminderType.task : ReminderType.idea;
         _reminder = ReminderItem(id: '', type: type, interests: '');
      } else {
        _reminder = await ReminderService.instance.getById(widget.payload!);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF070B14),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50))),
      );
    }

    final now = DateTime.now();
    final type = _reminder?.type ?? ReminderType.idea;
    final interests = _reminder?.interests ?? '';
    final content = DailyContent.forDate(now, type: type, interests: interests);

    const dayNames = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'];
    final dayName = dayNames[now.weekday % 7];

    const months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(
        title: Text(type == ReminderType.idea ? 'إلهام ايفورا' : 'مهمة ايفورا'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.5,
              colors: [
                (type == ReminderType.idea ? const Color(0xFF1565C0) : const Color(0xFF2E7D32)).withValues(alpha: 0.1),
                const Color(0xFF070B14),
              ],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Text(
                  '$dayName، ${now.day} ${months[now.month - 1]} ${now.year}',
                  style: const TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF141A2A),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: type == ReminderType.idea
                        ? const Color(0xFF2196F3).withValues(alpha: 0.2)
                        : const Color(0xFF4CAF50).withValues(alpha: 0.2),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (type == ReminderType.idea ? const Color(0xFF2196F3) : const Color(0xFF4CAF50)).withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: (type == ReminderType.idea ? const Color(0xFF2196F3) : const Color(0xFF4CAF50)).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        type == ReminderType.idea ? Icons.auto_awesome : Icons.task_alt,
                        size: 40,
                        color: type == ReminderType.idea ? const Color(0xFF64B5F6) : const Color(0xFF81C784),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (interests.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'اهتمامك: $interests',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                    Text(
                      content,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        height: 1.6,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final prompt = interests.isNotEmpty
                        ? interests
                        : (type == ReminderType.task
                            ? (_reminder?.title.isNotEmpty == true
                                ? 'ذكرني: ${_reminder!.title}'
                                : 'ما هي مهمتي الآن؟')
                            : 'اسرد لي الإلهام اليوم كما وعدت.');
                    ChatHandoff.openAssistantWith(prompt);
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: type == ReminderType.idea ? const Color(0xFF1565C0) : const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                  ),
                  child: const Text('افتح النقاش مع ايفورا', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() {}); // Simple refresh to get another content if randomized
                },
                child: const Text('اقتراح آخر', style: TextStyle(color: Colors.white38)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

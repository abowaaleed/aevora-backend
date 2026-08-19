import 'package:flutter/material.dart';

import '../client/client_reminders.dart';

class NotificationContentScreen extends StatelessWidget {
  final String? payload;

  const NotificationContentScreen({super.key, this.payload});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final type = (payload == 'test_task' || (payload?.endsWith('_task') == true))
        ? ReminderType.task
        : ReminderType.idea;
    final content = DailyContent.forDate(now, type: type);

    const dayNames = [
      'السبت', 'الأحد', 'الاثنين', 'الثلاثاء',
      'الأربعاء', 'الخميس', 'الجمعة',
    ];
    final dayName = dayNames[now.weekday % 7];

    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(
        title: Text(type == ReminderType.idea ? 'فكرة اليوم' : 'سلوك اليوم'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '$dayName، ${now.day} ${months[now.month - 1]} ${now.year}',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0C1828),
                    type == ReminderType.idea ? const Color(0xFF0D2137) : const Color(0xFF0D2710),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: type == ReminderType.idea
                      ? const Color(0xFF2196F3).withValues(alpha: 0.3)
                      : const Color(0xFF4CAF50).withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          (type == ReminderType.idea ? const Color(0xFF2196F3) : const Color(0xFF4CAF50))
                              .withValues(alpha: 0.25),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Icon(
                      type == ReminderType.idea ? Icons.lightbulb : Icons.check_circle,
                      size: 40,
                      color: type == ReminderType.idea ? const Color(0xFF64B5F6) : const Color(0xFF81C784),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    type == ReminderType.idea ? 'فكرة اليوم' : 'سلوك اليوم',
                    style: TextStyle(
                      color: type == ReminderType.idea ? const Color(0xFF64B5F6) : const Color(0xFF81C784),
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    content,
                    style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.8),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NotificationContentScreen(
                      payload: 'refresh_${type.name}',
                    ),
                  ),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('محتوى آخر'),
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF81C784), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'افتح التطبيق واستخدم المساعد للبدء في تنفيذ هذه الفكرة!',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

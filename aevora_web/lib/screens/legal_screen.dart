import 'package:flutter/material.dart';

import '../legal_content.dart';

/// قارئ مستندات (شروط الاستخدام / سياسة الخصوصية) — يعرض العنوان وآخر تحديث
/// وأقسام الوثيقة بأسلوب مطابق لهوية ايفورا.
class LegalScreen extends StatelessWidget {
  final LegalDocument document;
  const LegalScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(title: Text(document.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'آخر تحديث: ${document.updatedAt}',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 16),
          for (final section in document.sections) ...[
            Text(
              section.title,
              style: const TextStyle(
                color: Color(0xFF81C784),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              section.body,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.8,
              ),
            ),
            const SizedBox(height: 20),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

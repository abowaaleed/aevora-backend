import 'package:flutter/material.dart';

import '../client/client_consent.dart';
import '../legal_content.dart';
import 'legal_screen.dart';

/// شاشة «الموافقات والضوابط»: تعرض عناصر معالجة البيانات وخيارات التواصل
/// مع إمكانية قبول/رفض كل عنصر اختياري، وتُحفظ فوراً (محلياً ومع الحساب).
class ConsentsScreen extends StatefulWidget {
  const ConsentsScreen({super.key});

  @override
  State<ConsentsScreen> createState() => _ConsentsScreenState();
}

class _ConsentsScreenState extends State<ConsentsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(title: const Text('الموافقات والضوابط')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'نحترم خصوصيتك ونمنحك التحكم الكامل في بياناتك. وافقتك على هذه '
            'العناصر تُحفظ على جهازك وتُزامن مع حسابك عند تسجيل الدخول، '
            'ويمكنك تغييرها أو سحبها في أي وقت.',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.7),
          ),
          const SizedBox(height: 16),
          for (final item in consentCatalog)
            Card(
              color: const Color(0xFF141A2A),
              margin: const EdgeInsets.only(bottom: 10),
              child: CheckboxListTile(
                value: ConsentStore.get(item.id),
                onChanged: item.required
                    ? null
                    : (v) {
                        setState(() {});
                        ConsentStore.set(item.id, v ?? false);
                      },
                activeColor: const Color(0xFF4CAF50),
                title: Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  item.description,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              ConsentStore.setMany({
                for (final c in consentCatalog) c.id: c.required,
              });
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('سحبنا موافقاتك الاختيارية.')),
              );
            },
            icon: const Icon(Icons.undo),
            label: const Text('سحب كل الموافقات الاختيارية'),
          ),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF141A2A),
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.description_outlined,
                  color: Color(0xFF81C784)),
              title: const Text('اقرأ سياسة الخصوصية',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('كيف نجمع بياناتك ونستخدمها ونحميها',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: const Icon(Icons.chevron_left, color: Colors.white38),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LegalScreen(document: privacyDocument),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../config.dart';
import 'key_setup_screen.dart';

class SettingsScreen extends StatefulWidget {
  final KeySettings keys;
  final ValueChanged<KeySettings> onKeysChanged;
  final VoidCallback onLogout;
  const SettingsScreen({
    super.key,
    required this.keys,
    required this.onKeysChanged,
    required this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _clearing = false;

  Future<void> _openEdit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => KeySetupScreen(editing: true, initial: widget.keys),
      ),
    );
    if (changed == true) {
      final keys = await AppStorage.load();
      widget.onKeysChanged(keys);
    }
  }

  String _mask(String key) {
    if (key.isEmpty) return 'غير مضبوط';
    if (key.length <= 8) return '${key[0]}•••';
    return '${key.substring(0, 4)}••••••${key.substring(key.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('مفاتيحك الخاصة',
              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 8),
          _tile(
            icon: Icons.auto_awesome,
            title: 'مفتاح Gemini',
            value: _mask(widget.keys.geminiKey),
          ),
          _tile(
            icon: Icons.bolt,
            title: 'مفتاح Groq',
            value: _mask(widget.keys.groqKey),
          ),
          _tile(
            icon: Icons.mail_outline,
            title: 'البريد الإلكتروني',
            value: widget.keys.email.isEmpty ? 'غير مضبوط' : widget.keys.email,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openEdit,
            icon: const Icon(Icons.edit),
            label: const Text('تعديل المفاتيح'),
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),
          const Text(
            'كيف تعمل المفاتيح؟',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'تُحفظ المفاتيح على جهازك (localStorage) فقط، ولا تُرسل إلا إلى خادم ايفورا '
            'داخل رؤوس الطلبات ليستعملها في الرد عبر حسابك المجاني الخاص — بلا أي تسجيل.',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.7),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _clearing
                ? null
                : () {
                    setState(() => _clearing = true);
                    widget.onLogout();
                  },
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل الخروج (مسح المفاتيح من هذا المتصفح)'),
          ),
        ],
      ),
    );
  }

  Widget _tile({required IconData icon, required String title, required String value}) {
    return Card(
      color: const Color(0xFF141A2A),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF81C784)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(value, style: const TextStyle(color: Colors.white54)),
      ),
    );
  }
}

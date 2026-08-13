import 'package:flutter/material.dart';

import '../config.dart';

class KeySetupScreen extends StatefulWidget {
  final bool editing;
  final KeySettings? initial;
  const KeySetupScreen({super.key, this.editing = false, this.initial});

  @override
  State<KeySetupScreen> createState() => _KeySetupScreenState();
}

class _KeySetupScreenState extends State<KeySetupScreen> {
  final _geminiCtrl = TextEditingController();
  final _groqCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _saving = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _geminiCtrl.text = init.geminiKey;
      _groqCtrl.text = init.groqKey;
      _emailCtrl.text = init.email;
    }
  }

  Future<void> _save() async {
    final gemini = _geminiCtrl.text.trim();
    final groq = _groqCtrl.text.trim();
    if (gemini.isEmpty && groq.isEmpty) {
      setState(() => _status = 'أدخل مفتاحاً واحداً على الأقل (Gemini أو Groq).');
      return;
    }
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      await AppStorage.save(
        geminiKey: gemini,
        groqKey: groq,
        email: _emailCtrl.text.trim(),
      );
      if (mounted) {
        if (widget.editing) {
          Navigator.of(context).pop(true);
        } else {
          Navigator.of(context).pushReplacementNamed('/shell');
        }
      }
    } catch (e) {
      setState(() {
        _status = 'خطأ في الحفظ: $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  appName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.editing
                      ? 'تعديل مفاتيحك الخاصة'
                      : 'مفاتيحك الخاصة — حسابك عندك',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 24),
                const Text(
                  'أدخل مفاتيح API المجانية الخاصة بك (من Google AI Studio و/أو Groq). '
                  'تُرسل المفاتيح مباشرة من متصفحك إلى مزودي الخدمة، وتُحفظ على جهازك فقط.',
                  style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 24),
                _keyField(
                  controller: _geminiCtrl,
                  label: 'مفتاح Gemini (اختياري)',
                  hint: 'AIza...',
                  icon: Icons.auto_awesome,
                ),
                const SizedBox(height: 16),
                _keyField(
                  controller: _groqCtrl,
                  label: 'مفتاح Groq (اختياري)',
                  hint: 'gsk_...',
                  icon: Icons.bolt,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني (اختياري)',
                    labelStyle: TextStyle(color: Colors.white54),
                    hintText: 'name@example.com',
                    hintStyle: TextStyle(color: Colors.white24),
                    prefixIcon: Icon(Icons.mail_outline, color: Colors.white38),
                    filled: true,
                    fillColor: Color(0xFF0D1424),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                if (_status != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _status!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('حفظ والمتابعة',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _keyField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: Icon(icon, color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF0D1424),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

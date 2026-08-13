import 'package:flutter/material.dart';

import '../client/client_auth.dart';
import '../config.dart';
import '../widgets/google_g_button.dart';

/// شاشة الدخول الأولى: تسجيل الدخول بحساب Google ليرافق بيانات المستخدم
/// على أي متصفح/هاتف، مع إمكانية المتابعة محلياً بدون حساب.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await signInWithGoogle();
      if (user == null && mounted) {
        setState(() => _error = 'تعذر تسجيل الدخول. حاول مرة أخرى.');
      }
      // عند النجاح يُعيد التوجيه تلقائياً عبر مراقب حالة الجلسة.
    } catch (e) {
      if (mounted) {
        setState(() => _error = _describeError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// تسجيل الدخول بنافذة Redirect — بديل يعمل حتى لو حُجبت النوافذ المنبثقة.
  Future<void> _signInRedirect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await signInWithGoogleRedirect();
      // بعد العودة من Google تُكمل الجلسة تلقائياً (انظر initFirebase).
    } catch (e) {
      if (mounted) setState(() => _error = _describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describeError(Object e) {
    final s = e.toString();
    // استخراج رمز خطأ Firebase مثل auth/operation-not-allowed
    final code = RegExp(r'auth/[a-z-]+').firstMatch(s)?.group(0);
    if (code != null) {
      return switch (code) {
        'auth/operation-not-allowed' =>
          'لم يُفعَّل تسجيل الدخول بحساب Google بعد في إعدادات المشروع '
              '(Authentication → Sign-in method).',
        'auth/popup-blocked' =>
          'المتصفح حجب النافذة المنبثقة. جرّب "تسجيل الدخول بنافذة بديلة" بالأسفل.',
        'auth/unauthorized-domain' =>
          'نطاق الموقع غير مصرّح به. أضف abowaaleed.github.io في قائمة '
              'Authorized domains بمشروع Firebase.',
        'auth/cancelled-popup-request' => 'أُلغيت النافذة. حاول مرة أخرى.',
        _ => 'فشل تسجيل الدخول ($code). تأكد من إعدادات Authentication في Firebase.',
      };
    }
    return 'فشل تسجيل الدخول: $s';
  }

  void _continueLocal() {
    Navigator.of(context).pushNamedAndRemoveUntil('/setup', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1D3A1D),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: Color(0xFF4CAF50), size: 40),
                ),
                const SizedBox(height: 20),
                const Text(
                  appName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'صديقك الذكي لتعلم الإنجليزية',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 28),
                Card(
                  color: const Color(0xFF141A2A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'سجّل دخولك بحساب Google',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'لتبقى محادثاتك ومهامك وعدّاداتك ملازمة لك على أي '
                          'متصفح أو هاتف. (بياناتك تُخزن بأمان تحت حسابك وتُشفَّر '
                          'اتصالاتك)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 16),
                        GoogleGButton(
                          label: 'المتابعة بحساب Google',
                          onPressed: _busy ? null : _signIn,
                          enabled: !_busy,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : _signInRedirect,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                          ),
                          child: const Text(
                            'تسجيل الدخول بنافذة بديلة',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        if (_busy) ...[
                          const SizedBox(height: 14),
                          const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF4CAF50),
                              ),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A1414),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.redAccent),
                            ),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.redAccent, fontSize: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: _busy ? null : _continueLocal,
                  child: const Text(
                    'المتابعة بدون حساب (محلي على هذا الجهاز فقط)',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '🔐 خصوصية تامة: تُرسل محادثاتك للنموذج الذكي للإجابة فقط، '
                  'وتبقى مفاتيحك على جهازك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../client/client_auth.dart';
import '../client/client_plan.dart';
import '../client/client_rag.dart';
import '../client/client_sync.dart';
import '../client/client_usage.dart';
import '../config.dart';
import '../legal_content.dart';
import 'consents_screen.dart';
import 'document_screen.dart';
import 'key_setup_screen.dart';
import 'legal_screen.dart';
import 'memory_screen.dart';
import 'subscription_screen.dart';

class SettingsScreen extends StatefulWidget {
  final KeySettings keys;
  final ValueChanged<KeySettings> onKeysChanged;
  final VoidCallback onLogout;
  final Future<void> Function() onAccountSignOut;
  const SettingsScreen({
    super.key,
    required this.keys,
    required this.onKeysChanged,
    required this.onLogout,
    required this.onAccountSignOut,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _clearing = false;
  bool _signingOut = false;
  bool _uploading = false;
  Map<String, dynamic>? _usage;
  bool _usageLoading = false;
  String? _usageError;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    setState(() {
      _usageLoading = true;
      _usageError = null;
    });
    try {
      final u = await LocalUsage.today();
      if (!mounted) return;
      setState(() => _usage = u);
    } catch (e) {
      if (!mounted) return;
      setState(() => _usageError = 'تعذر جلب الاستهلاك: $e');
    } finally {
      if (mounted) setState(() => _usageLoading = false);
    }
  }

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

  Future<void> _signOutAccount() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    await widget.onAccountSignOut();
    // توجّه الواجهة إلى شاشة الدخول تلقائياً عبر مراقب الجلسة.
  }

  /// رفع مستندات PDF / Word / TXT / صور من الإعدادات وفهرستها للبحث فيها.
  Future<void> _pickAndIndex() async {
    if (_uploading) return;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedUploadExtensions,
      );
      if (files.isEmpty) return;

      if (!mounted) return;
      setState(() => _uploading = true);

      var failed = 0;
      final total = files.length;
      for (final f in files) {
        try {
          final bytes = await f.readAsBytes();
          await indexLocalFile(f.name, bytes);
          // رفع الملف مع الحساب (إن كان مسجلاً) ليتوفر في أي جهاز آخر.
          SyncStore.schedulePush();
        } catch (_) {
          failed++;
        }
        if (mounted) setState(() {});
      }

      if (mounted) {
        setState(() => _uploading = false);
        DocumentScreen.refreshTick.value++;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            failed == 0
                ? 'تمت فهرسة $total ملفاً بنجاح.'
                : 'تمت فهرسة ${total - failed} من $total ملفاً ($failed فشل).',
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشل الرفع: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _subscriptionCard(),
          const SizedBox(height: 16),
          if (isAuthEnabled) ..._accountSection(),
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
          Card(
            color: const Color(0xFF141A2A),
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.psychology_rounded, color: Color(0xFF81C784)),
              title: const Text('ذاكرة المساعد', style: TextStyle(color: Colors.white)),
              subtitle: const Text('تصفح كل ما يعرفه عنك: اسمك، اهتماماتك، حقائقك، مهامك',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: const Icon(Icons.chevron_left, color: Colors.white38),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MemoryScreen(keys: widget.keys)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFF141A2A),
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: _uploading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF81C784)),
                    )
                  : const Icon(Icons.upload_file, color: Color(0xFF81C784)),
              title: Text(
                _uploading
                    ? 'جارٍ الفهرسة...'
                    : 'رفع مستندات (PDF / Word / TXT / صور)',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                _uploading ? 'يرجى الانتظار...' : acceptedFormatsLabel,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_left, color: Colors.white38),
              onTap: _uploading ? null : _pickAndIndex,
            ),
          ),
          const SizedBox(height: 24),
          const Text('استهلاك الخطة المجانية اليوم',
              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 4),
          Text(
            _usage?['date'] == null
                ? 'محفوظ على هذا المتصفح'
                : 'يوم ${_usage?['date']}',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _usageCard(),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),
          const Text(
            'السياسة والشروط',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 8),
          _legalTile(
            icon: Icons.description_outlined,
            title: 'شروط الاستخدام',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const LegalScreen(document: termsDocument),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _legalTile(
            icon: Icons.privacy_tip_outlined,
            title: 'سياسة الخصوصية',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const LegalScreen(document: privacyDocument),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _legalTile(
            icon: Icons.admin_panel_settings_outlined,
            title: 'الموافقات والضوابط',
            subtitle: 'البيانات، الموافقات، والتواصل',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConsentsScreen()),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'كيف تعمل المفاتيح؟',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'تعمل ايفورا بالكامل داخل متصفحك: تُحفظ مفاتيحك في هذا المتصفح '
            'وتُرسل الطلبات مباشرة من جهازك إلى Gemini وGroq بحسابك المجاني — '
            'دون أي خادم وسيط. وكل ملفاتك وذاكرتك ومحادثاتك محفوظة محلياً على '
            'جهازك (IndexedDB)، وعند تسجيل الدخول بحساب Google تُزامن مع '
            'حسابك لتتوفر على أي جهاز آخر.',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.7),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'ايفورا • الإصدار $appVersion',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
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

  /// قسم الحساب والمزامنة: يظهر عندما يكون Firebase مفعّلاً.
  List<Widget> _accountSection() {
    final signedIn = isSignedIn;
    final email = currentEmail;
    final name = currentDisplayName;
    return [
      const Text('الحساب والمزامنة',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
      const SizedBox(height: 8),
      Card(
        color: const Color(0xFF141A2A),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!signedIn) ...[
                const Row(
                  children: [
                    Icon(Icons.cloud_off, color: Colors.white54, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'غير مسجل الدخول — بياناتك محفوظة على هذا الجهاز فقط.',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushNamedAndRemoveUntil(
                            '/login', (_) => false),
                    icon: const Icon(Icons.login),
                    label: const Text('تسجيل الدخول بحساب Google'),
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF1D3A1D),
                      child: Text(
                        (name != null && name.isNotEmpty)
                            ? name[0].toUpperCase()
                            : (email?.isNotEmpty ?? false)
                                ? email![0].toUpperCase()
                                : '?',
                        style: const TextStyle(
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (name != null && name.isNotEmpty) ? name : 'حساب Google',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                          if (email != null && email.isNotEmpty)
                            Text(
                              email,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Row(
                  children: [
                    Icon(Icons.sync_rounded, color: Color(0xFF81C784), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'المزامنة نشطة: محادثاتك ومفاتيحك وملفاتك ومهامك '
                        'وعدّاداتك تتبعك على أي متصفح أو هاتف.',
                        style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _signingOut ? null : _signOutAccount,
                    icon: const Icon(Icons.logout),
                    label: Text(_signingOut
                        ? 'جارٍ تسجيل الخروج...'
                        : 'تسجيل الخروج من الحساب'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  Widget _usageCard() {
    if (_usageLoading && _usage == null) {
      return const Card(
        color: Color(0xFF141A2A),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_usageError != null) {
      return Card(
        color: const Color(0xFF141A2A),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_usageError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _loadUsage,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    final u = _usage;
    if (u == null) return const SizedBox.shrink();
    return Card(
      color: const Color(0xFF141A2A),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          _usageRow('chat', 'محادثة ايفورا (Gemini)',
              u['gemini'] as Map<String, dynamic>?),
            const SizedBox(height: 14),
            _usageRow('mic', 'التعرف على الصوت (Whisper عبر Groq)',
                u['stt_groq'] as Map<String, dynamic>?),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.record_voice_over_rounded,
                    color: Color(0xFF81C784), size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('النطق الاحترافي (صوت ايفورا)',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
                Text(
                  '${(u['tts']?['requests'] as num?)?.toInt() ?? 0} طلب · '
                  '${(u['tts']?['chars'] as num?)?.toInt() ?? 0} حرف',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'الصوت الاحترافي من Gemini TTS (نموذج تجريبي بحدود يومية أضيق من '
              'المحادثة) بمفتاحك؛ عند استنفادها يتحول النطق تلقائياً لصوت المتصفح.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('رسائل المساعد الشخصي: ',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                Text(
                  '${(u['companion'] as num?)?.toInt() ?? 0} رسالة',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'هذه عدّادات تقريبية على جهازك ولا تعكس بالضرورة حصة المزود الفعلية '
              'التي تفرضها Google/Groq وقد تتغير. الطلبات تُحسب يومياً على كل من '
              '«في الدقيقة» (RPM) و«في اليوم» (RPD): فخطأ الازدحام المؤقت «high '
              'demand» من Gemini يظهر رغم بقاء الحصة اليومية ولا يعني نفادها — '
              'انتظر دقيقة وأعد المحاولة.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.6),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _usageLoading ? null : _loadUsage,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(_usageLoading ? 'جارٍ التحديث...' : 'تحديث'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _usageRow(String iconKind, String label, Map<String, dynamic>? data) {
    final used = (data?['used'] as num?)?.toInt() ?? 0;
    final limit = (data?['limit'] as num?)?.toInt() ?? 0;
    final remaining = (data?['remaining'] as num?)?.toInt() ?? 0;
    final rpm = (data?['rpm'] as num?)?.toInt() ?? 0;
    final ratio = limit > 0 ? used / limit : 0.0;
    final color = ratio >= 0.9
        ? Colors.redAccent
        : ratio >= 0.6
            ? Colors.orange
            : const Color(0xFF81C784);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(iconKind == 'mic' ? Icons.mic : Icons.auto_awesome,
                color: const Color(0xFF81C784), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            Text('$used / $limit',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          rpm > 0 ? 'حتى $rpm طلبات/دقيقة · المتبقي اليوم: $remaining' : '',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
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

  /// بطاقة «الاشتراك والترقية» البارزة في أعلى الإعدادات.
  Widget _subscriptionCard() {
    return ValueListenableBuilder<PlanState>(
      valueListenable: PlanStore.current,
      builder: (context, state, _) {
        final premium = state.isPremium;
        return Card(
          color: premium ? const Color(0xFF1A2B1A) : const Color(0xFF141A2A),
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: premium ? const Color(0xFF81C784) : Colors.white12,
              width: premium ? 1.4 : 1,
            ),
          ),
          child: ListTile(
            leading: Icon(
              premium ? Icons.workspace_premium_rounded : Icons.auto_awesome,
              color: premium ? const Color(0xFF81C784) : Colors.white54,
            ),
            title: Text(
              premium ? 'اشتراكك: ${state.label}' : 'الاشتراك والترقية',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              premium
                  ? 'نطاق الاحترافي بلا حدود + تصدير بدون ترويج'
                  : 'النطق الاحترافي بلا حدود، التصدير بدون ترويج، وخطط بدون مفاتيح',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!premium)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('ترقية',
                        style: TextStyle(
                            color: Color(0xFF070B14),
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ),
                const Icon(Icons.chevron_left, color: Colors.white38),
              ],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SubscriptionScreen(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _legalTile({
    required IconData icon,
    required String title,
    String subtitle = '',
    required VoidCallback onTap,
  }) {
    return Card(
      color: const Color(0xFF141A2A),
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF81C784)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: const Icon(Icons.chevron_left, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }
}

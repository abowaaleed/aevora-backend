import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../client/client_auth.dart';
import '../client/client_llm.dart';
import '../client/client_plan.dart';
import '../client/client_rag.dart';
import '../client/client_sync.dart';
import '../client/client_upload.dart';
import '../client/client_usage.dart';
import '../config.dart';
import '../legal_content.dart';
import '../widgets/rtl.dart';
import '../widgets/upload_progress_dialog.dart';
import 'consents_screen.dart';
import 'document_screen.dart';
import 'key_setup_screen.dart';
import 'legal_screen.dart';
import 'memory_screen.dart';
import 'reminders_screen.dart';
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
  Map<String, dynamic>? _docUsage;

  @override
  void initState() {
    super.initState();
    SyncStore.cloudAppliedTick.addListener(_onCloudData);
    activeChatEngine.addListener(_onEngineChanged);
    LocalUsage.changed.addListener(_onUsageChanged);
    _loadUsage();
  }

  @override
  void dispose() {
    LocalUsage.changed.removeListener(_onUsageChanged);
    SyncStore.cloudAppliedTick.removeListener(_onCloudData);
    activeChatEngine.removeListener(_onEngineChanged);
    super.dispose();
  }

  void _onUsageChanged() {
    _loadUsage(silent: true);
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  /// بيانات (عدادات/ملفات) وصلت من السحابة بعد بناء الشاشة — أعد التحميل
  /// تلقائياً حتى لا تبقى العدادات صفراً بانتظار تحديث يدوي.
  void _onCloudData() {
    _loadUsage(silent: true);
  }

  Future<void> _loadUsage({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _usageLoading = true;
        _usageError = null;
      });
    }
    try {
      final u = await LocalUsage.today();
      final docs = await documentUsageSummary();
      if (!mounted) return;
      setState(() {
        _usage = u;
        _docUsage = docs;
      });
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

  /// رفع مستندات PDF / Word / TXT / صور من الإعدادات وفهرستها للبحث فيها —
  /// عبر نافذة تقدم موحّدة تفحص حدود الخطة أولاً.
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

      final result = await showUploadFlow(
        context,
        files: files,
        plan: PlanStore.current.value,
      );
      if (!mounted) return;
      setState(() => _uploading = false);

      if (result == null) return; // مُنع الرفع بالحدود (نافذة الترقي ظهرت).

      DocumentScreen.refreshTick.value++;
      final msg = result.uploaded == 0
          ? 'فشل رفع الملفات:\n${result.errors.join('\n')}'
          : result.failed == 0
              ? 'تمت فهرسة ${result.uploaded} ملفاً بنجاح.'
              : 'تمت فهرسة ${result.uploaded} ملفاً (فشل ${result.failed}):\n'
                  '${result.errors.join('\n')}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
          const SizedBox(height: 10),
          const Text('مزودون قريباً',
              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white70)),
          const SizedBox(height: 6),
          _comingKey('ChatGPT (OpenAI)'),
          _comingKey('Anthropic Claude'),
          _comingKey('DeepSeek'),
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
            color: const Color(0xFF1E5B45),
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.alarm_rounded, color: Color(0xFF4CE0A3)),
              title: const Text('رسائل ايفورا الذكية',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              subtitle: const Text('أفكار وسلوكيات ومهام يومية — سهلة وواضحة',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
              trailing: const Icon(Icons.chevron_left, color: Colors.white38),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RemindersScreen()),
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
          _usageRow('chat', 'طلبات Gemini اليوم (محادثة وتحليلات خلفية)',
              u['gemini'] as Map<String, dynamic>?,
              active: activeChatEngine.value == ChatEngine.gemini),
            const SizedBox(height: 14),
            _usageRow('bolt', 'دردشة Groq الاحتياطية (Llama)',
                u['groq_chat'] as Map<String, dynamic>?,
                active: activeChatEngine.value == ChatEngine.groq),
            const SizedBox(height: 14),
            _usageRow('mic', 'التعرف على الصوت (Whisper عبر Groq)',
                u['stt_groq'] as Map<String, dynamic>?),
            const SizedBox(height: 12),
            _ttsCharsRow(u['tts'] as Map<String, dynamic>?),
            const SizedBox(height: 12),
            _backupVoiceRow(u['backup_voice'] as num?),
            const SizedBox(height: 4),
            const Text(
              'النطق الاحترافي في خطتك «المجانية» يعمل عبر صوت إيدج الطبيعي '
              'المجاني — بلا حدود ولا يستهلك حصة Gemini؛ وعند تعذره يتحول '
              'تلقائياً إلى صوت المتصفح. النطق المتقدم عبر Gemini TTS مخصص '
              'لخطط «مميز/مُدارة».',
              textAlign: TextAlign.right,
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
            const SizedBox(height: 12),
            _documentsRow(),
            const SizedBox(height: 10),
            const Text(
              'كيف يُحسب الطلب؟ كل طلب = استدعاء واحد لواجهة Gemini: رسالة '
              'محادثة واحدة، أو تحليل خلفي تلقائي (مرة كل بضع رسائل)، أو رسالة '
              'المساعد — ليس لكل كلمة. العدادات هنا على جهازك، والحصة الفعلية '
              'يفرضها المزوّد على مفتاحك ومشروعك وقد تتقاسمها تطبيقات أخرى بنفس '
              'المفتاح. أخطاء «في الدقيقة» (RPM) تزول خلال دقيقة، وأخطاء '
              '«الازدحام المؤقت» تزول خلال دقائق — ولا تعني نفاد حصتك اليومية. '
              'وعند تعذّر Gemini تماماً تنتقل المحادثة تلقائياً وبصمت إلى Groq '
              'إن وُجد مفتاحها، فالتطبيق لا يتوقف أبداً.',
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.6),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _usageLoading ? null : _loadUsage,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(_usageLoading ? 'جارٍ التحديث...' : 'تحديث (اختياري)'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _usageRow(String iconKind, String label, Map<String, dynamic>? data,
      {bool active = false}) {
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
    return Rtl(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconKind == 'mic'
                  ? Icons.mic
                  : iconKind == 'bolt'
                      ? Icons.bolt
                      : Icons.auto_awesome,
                  color: const Color(0xFF81C784),
                  size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
              if (active) ...[
                const SizedBox(width: 6),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.9),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
              ],
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
      ),
    );
  }

  /// صف النطق الاحترافي بعدّاد أحرف وبار تقدم مقابل الحد المجاني اليومي
  /// (بلا حدود لمشتركي «مميز/مُدارة»).
  Widget _ttsCharsRow(Map<String, dynamic>? tts) {
    final premium = PlanStore.current.value.isPremium;
    if (!premium) {
      // الخطة المجانية: صوت إيدج الاحترافي مجاني وبلا حدود ولا يستهلك حصة Gemini.
      return Rtl(
        child: Row(
          children: [
            const Icon(Icons.record_voice_over_rounded,
                color: Color(0xFF81C784), size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('النطق الاحترافي (صوت إيدج)',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
            Text('مجاني · بلا حدود',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );
    }
    final used = (tts?['chars'] as num?)?.toInt() ?? 0;
    final requests = (tts?['requests'] as num?)?.toInt() ?? 0;
    return Rtl(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                '$used حرف',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: 1.0,
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF81C784)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'بلا حدود (خطتك «${PlanStore.current.value.label}»)· $requests طلب اليوم',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// صف الصوت الاحتياطي المدمج في الجهاز — عدد الاستخدامات اليومية.
  Widget _backupVoiceRow(num? count) {
    final n = count?.toInt() ?? 0;
    return Rtl(
      child: Row(
        children: [
          const Icon(Icons.record_voice_over, color: Color(0xFF81C784), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'الصوت الاحتياطي (جهازك): $n استخدام اليوم',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// صف حصة المستندات: العدد والمساحة مقابل حدود الخطة مع زر ترقية.
  Widget _documentsRow() {
    return ValueListenableBuilder<PlanState>(
      valueListenable: PlanStore.current,
      builder: (context, plan, _) {
        final quota = quotaForPlan(plan);
        final count = (_docUsage?['count'] as num?)?.toInt() ?? 0;
        final bytes = (_docUsage?['bytes'] as num?)?.toInt() ?? 0;
        final ratio = count / quota.maxFiles;
        final nearLimit = !plan.isPremium && ratio >= 0.8;
        final color = nearLimit ? Colors.orangeAccent : const Color(0xFF81C784);
        return Rtl(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_outlined,
                      color: Color(0xFF81C784), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'المستندات: $count من ${quota.maxFiles} · '
                      '${_sizeLabel(bytes)} من ${_sizeLabel(quota.maxStorageBytes)}',
                      style: TextStyle(
                          color: nearLimit ? Colors.orangeAccent : Colors.white,
                          fontSize: 13),
                    ),
                  ),
                  if (!plan.isPremium)
                    InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SubscriptionScreen()),
                      ),
                      child: const Text('ترقية',
                          style: TextStyle(
                              color: Color(0xFF81C784),
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
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
            ],
          ),
        );
      },
    );
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes بايت';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} ك.ب';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }

  Widget _comingKey(String title) {
    return Card(
      color: const Color(0xFF101624),
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: const Icon(Icons.lock_clock_outlined, color: Colors.white38),
        title: Text(title, style: const TextStyle(color: Colors.white70)),
        subtitle: const Text('سيُضاف حقل المفتاح لاحقاً دون تغيير طريقة الاستخدام',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        enabled: false,
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

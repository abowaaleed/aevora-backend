import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../client/client_plan.dart';
import '../client/client_rag.dart';
import '../client/client_storage.dart';
import '../client/client_sync.dart';
import '../config.dart';
import '../widgets/rtl.dart';
import '../widgets/upload_progress_dialog.dart';
import 'subscription_screen.dart';

class DocumentScreen extends StatefulWidget {
  /// إشارة لتحديث قائمة الملفات من أي مكان (مثل بعد رفع من الإعدادات).
  static final ValueNotifier<int> refreshTick = ValueNotifier<int>(0);

  final KeySettings keys;
  const DocumentScreen({super.key, required this.keys});

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocItem {
  final String filename;
  final String status;
  final int size;
  _DocItem(this.filename, this.status, this.size);
}

class _DocumentScreenState extends State<DocumentScreen> {
  List<_DocItem> _files = [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;
  int _storageBytes = 0;

  @override
  void initState() {
    super.initState();
    DocumentScreen.refreshTick.addListener(_onRefreshTick);
    SyncStore.cloudAppliedTick.addListener(_onRefreshTick);
    _load();
  }

  @override
  void dispose() {
    DocumentScreen.refreshTick.removeListener(_onRefreshTick);
    SyncStore.cloudAppliedTick.removeListener(_onRefreshTick);
    super.dispose();
  }

  void _onRefreshTick() {
    _load();
  }

  /// «تحديث» من شريط الأعلى: يسحب الحالة كاملة من السحابة ثم يعيد قراءة
  /// الملفات المحلية — فلا يبقى التحديث محلياً فقط (كان الزر يبدو بلا أثر
  /// لأنه كان يعيد قراءة IndexedDB المحلية وحدها).
  Future<void> _refreshFromCloud() async {
    await SyncStore.pullNow();
    await _load();
  }

  Future<void> _load() async {
    try {
      final rows = await LocalDb.listFiles();
      if (!mounted) return;
      setState(() {
        _files = rows
            .map((f) => _DocItem(
                (f['name'] ?? '').toString(),
                (f['status'] ?? '').toString(),
                (f['size'] as num?)?.toInt() ?? 0))
            .toList();
        _storageBytes = rows.fold<int>(
            0, (s, f) => s + ((f['size'] as num?)?.toInt() ?? 0));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// رفع ملفات PDF / Word / TXT / صور وفهرستها محلياً للبحث في المحادثة —
  /// عبر نافذة تقدم موحّدة تفحص حدود الخطة أولاً.
  Future<void> _pickAndUpload() async {
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
      await _load();
      if (!mounted) return;
      final msg = result.uploaded == 0
          ? 'فشل رفع الملفات:\n${result.errors.join('\n')}'
          : result.failed == 0
              ? 'تمت فهرسة ${result.uploaded} ملفاً بنجاح.'
              : 'تمت فهرسة ${result.uploaded} ملفاً (فشل ${result.failed}):\n'
                  '${result.errors.join('\n')}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل الرفع: $e')));
    }
  }

  Future<void> _viewContent(_DocItem item) async {
    try {
      final rows = await LocalDb.listFiles();
      Map<String, dynamic>? meta;
      for (final f in rows) {
        if ((f['name'] ?? '') == item.filename) {
          meta = f;
          break;
        }
      }
      final content = (meta?['text'] ?? '').toString();
      if (content.trim().isEmpty) {
        throw Exception('لا يوجد نص مستخرج من هذا الملف.');
      }
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF141A2A),
          title: Text(item.filename, style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: Colors.white70, height: 1.6),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Future<void> _delete(_DocItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141A2A),
        title: const Text('حذف المستند',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          'سيُحذف «${item.filename}» نهائياً من جهازك ومن كل أجهزتك المزامنة بحسابك.',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائياً'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(const SnackBar(
        content: Text('جارٍ حذف الملف ومزامنة الحذف مع كل أجهزتك...'),
        duration: Duration(seconds: 20),
      ));
      final ok = await SyncStore.deleteFileEverywhere(item.filename);
      await _load();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(
          ok
              ? 'تم حذف «${item.filename}» من جهازك وكل أجهزتك.'
              : 'حُذف الملف من جهازك، لكن مزامنة الحذف مع السحابة لم تكتمل — '
                  'ستُعاد المحاولة تلقائياً ولن يعود الملف.',
          textDirection: TextDirection.rtl,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  /// حذف جميع المستندات دفعة واحدة من الجهاز ومن كل الأجهزة المزامنة.
  Future<void> _deleteAll() async {
    final names = _files.map((f) => f.filename).toList();
    if (names.isEmpty || _uploading) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141A2A),
        title: const Text('حذف جميع المستندات',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          'سيُحذف ${names.length} مستند نهائياً من جهازك ومن كل أجهزتك '
          'المزامنة بحسابك، ولا يمكن التراجع عن هذا.',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائياً'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(const SnackBar(
        content: Text('جارٍ حذف المستندات ومزامنة الحذف مع كل أجهزتك...'),
        duration: Duration(seconds: 20),
      ));
      final ok = await SyncStore.deleteAllEverywhere(names);
      await _load();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(
          ok
              ? 'تم حذف جميع المستندات من جهازك وكل أجهزتك.'
              : 'حُذفت المستندات من جهازك، لكن مزامنة الحذف مع السحابة لم تكتمل — '
                  'ستُعاد المحاولة تلقائياً ولن تعود الملفات على أجهزتك.',
          textDirection: TextDirection.rtl,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes بايت';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} ك.ب';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }

  /// شريط حصة المستندات: العدد والمساحة مقابل حدود الخطة مع زر ترقية.
  Widget _quotaBanner() {
    return ValueListenableBuilder<PlanState>(
      valueListenable: PlanStore.current,
      builder: (context, plan, _) {
        final quota = quotaForPlan(plan);
        final count = _files.length;
        final ratio = count / quota.maxFiles;
        final nearLimit = !plan.isPremium && ratio >= 0.8;
        final color = nearLimit
            ? Colors.orangeAccent
            : const Color(0xFF81C784);
        return Container(
          width: double.infinity,
          color: const Color(0xFF0D1422),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Rtl(
            child: Row(
              children: [
                Icon(Icons.folder_outlined, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مستنداتك: $count من ${quota.maxFiles} · '
                        'مساحة ${_sizeLabel(_storageBytes)} من ${_sizeLabel(quota.maxStorageBytes)}',
                        style: TextStyle(
                          color: nearLimit
                              ? Colors.orangeAccent
                              : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio.clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!plan.isPremium)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SubscriptionScreen()),
                    ),
                    icon: const Icon(Icons.workspace_premium_outlined, size: 16),
                    label: const Text('ترقية',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(
        title: const Text('المستندات'),
        actions: [
          if (_files.isNotEmpty)
            IconButton(
              tooltip: 'حذف جميع المستندات من كل الأجهزة',
              onPressed: _deleteAll,
              icon: const Icon(Icons.delete_sweep_outlined),
              color: Colors.redAccent,
            ),
          IconButton(
            tooltip: 'مزامنة مع السحابة',
            onPressed: _refreshFromCloud,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
            )
          : Column(
              children: [
                _quotaBanner(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
                    ),
                  ),
                Expanded(
                  child: _files.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد مستندات بعد.\nارفع ملفات PDF أو Word أو TXT أو صور من زر «رفع ملف» بالأسفل.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _files.length,
                          itemBuilder: (context, index) {
                            final f = _files[index];
                            return Card(
                              color: const Color(0xFF141A2A),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF81C784),
                                ),
                                title: Text(f.filename,
                                    style: const TextStyle(color: Colors.white)),
                                subtitle: Text(
                                  'جاهز · ${_sizeLabel(f.size)}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: () => _viewContent(f),
                                      icon: const Icon(Icons.visibility),
                                      color: Colors.white54,
                                    ),
                                    IconButton(
                                      onPressed: () => _delete(f),
                                      icon: const Icon(Icons.delete_outline),
                                      color: Colors.redAccent,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    acceptedFormatsLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ),
      floatingActionButton: _uploading
          ? null
          : FloatingActionButton.extended(
              onPressed: _pickAndUpload,
              backgroundColor: const Color(0xFF4CAF50),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('رفع ملف'),
            ),
    );
  }
}

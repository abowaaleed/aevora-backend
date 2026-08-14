import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../client/client_rag.dart';
import '../client/client_storage.dart';
import '../client/client_sync.dart';
import '../config.dart';

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

  @override
  void initState() {
    super.initState();
    DocumentScreen.refreshTick.addListener(_onRefreshTick);
    _load();
  }

  @override
  void dispose() {
    DocumentScreen.refreshTick.removeListener(_onRefreshTick);
    super.dispose();
  }

  void _onRefreshTick() {
    _load();
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

  /// رفع ملفات PDF / TXT وفهرستها محلياً لتصبح قابلة للبحث في المحادثة.
  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt'],
      );
      if (files.isEmpty) return;

      if (!mounted) return;
      setState(() => _uploading = true);

      var failed = 0;
      for (final f in files) {
        try {
          final bytes = await f.readAsBytes();
          await indexLocalFile(f.name, bytes);
          SyncStore.schedulePush();
        } catch (_) {
          failed++;
        }
      }

      if (!mounted) return;
      setState(() => _uploading = false);
      DocumentScreen.refreshTick.value++;
      _load();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          failed == 0
              ? 'تمت فهرسة ${files.length} ملفاً بنجاح.'
              : 'تمت فهرسة ${files.length - failed} من ${files.length} ملفاً ($failed فشل).',
        ),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشل الرفع: $e')));
      }
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
    try {
      await LocalDb.deleteFile(item.filename);
      await LocalDb.clearChunksForFile(item.filename);
      SyncStore.schedulePush();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes بايت';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} ك.ب';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(
        title: const Text('المستندات'),
        actions: [
          IconButton(
            onPressed: _load,
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
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
                    ),
                  ),
                Expanded(
                  child: _files.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد مستندات بعد.\nارفع ملفات PDF أو TXT من زر «رفع ملف» بالأسفل.',
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

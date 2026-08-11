import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../config.dart';

class _DocItem {
  final String filename;
  final String status;
  final String progress;
  _DocItem(this.filename, this.status, this.progress);
}

class DocumentScreen extends StatefulWidget {
  final KeySettings keys;
  const DocumentScreen({super.key, required this.keys});

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  List<_DocItem> _files = [];
  bool _loading = true;
  String? _error;
  bool _uploading = false;
  String _uploadStatus = '';

  @override
  void initState() {
    super.initState();
    _load();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Timer? _refreshTimer;

  /// تحديث تلقائي كل 4 ثوانٍ ما دامت هناك ملفات قيد المعالجة/الاستعادة.
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_uploading) {
        final hasPending = _files.any((f) => f.status != 'indexed');
        if (hasPending) _load(silent: true);
      }
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await apiGet('/rag/files', widget.keys);
      if (res.statusCode != 200) {
        throw Exception('الخادم رفض الطلب (${res.statusCode})');
      }
      final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      setState(() {
        _files = list
            .map((f) => _DocItem(
                (f['filename'] ?? '').toString(),
                (f['status'] ?? '').toString(),
                (f['progress'] ?? '').toString()))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (silent) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickAndUpload() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'txt', 'xlsx', 'xls', 'csv', 'jpg', 'jpeg', 'png', 'webp'],
      );
      if (result == null || result.files.isEmpty) return;

      final files = result.files.where((f) => f.bytes != null).toList();
      if (files.isEmpty) {
        throw Exception('لم يُقرأ أي ملف.');
      }

      setState(() {
        _uploading = true;
        _error = null;
        _uploadStatus = '';
      });

      var uploaded = 0;
      final total = files.length;
      for (final f in files) {
        if (!mounted) return;
        setState(() {
          _uploadStatus = 'جاري رفع (${uploaded + 1}/$total): ${f.name}';
        });
        try {
          final res = await apiUpload('/rag/upload', widget.keys, [
            MapEntry('files', Uint8ListBytes(f.bytes!, f.name)),
          ]);
          final body = await res.stream.bytesToString();
          if (res.statusCode != 200) {
            setState(() => _error = 'فشل رفع «${f.name}» (${res.statusCode}): $body');
          }
        } catch (e) {
          setState(() => _error = 'فشل رفع «${f.name}»: $e');
          await Future.delayed(const Duration(seconds: 1));
        }
        uploaded++;
      }

      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadStatus = uploaded == total ? 'تم رفع جميع الملفات' : 'اكتمل الرفع';
        });
      }
      await _load();
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) _load(silent: true);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = 'فشل الرفع: $e';
        });
      }
    }
  }

  Future<void> _viewContent(_DocItem item) async {
    try {
      final res = await apiGet(
          '/rag/files/${Uri.encodeComponent(item.filename)}/content', widget.keys);
      if (res.statusCode != 200) {
        throw Exception('غير جاهز بعد (${res.statusCode})');
      }
      final content = (jsonDecode(res.body)['content'] ?? '').toString();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Future<void> _delete(_DocItem item) async {
    try {
      final res = await apiDelete(
          '/rag/files/${Uri.encodeComponent(item.filename)}', widget.keys);
      if (res.statusCode != 200) {
        throw Exception('حذف فشل (${res.statusCode})');
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
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
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      FilledButton.icon(
                        onPressed: _uploading ? null : _pickAndUpload,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                        ),
                        icon: _uploading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.upload_file),
                        label: Text(
                          _uploading ? 'رفع جارٍ...' : 'رفع مستندات (PDF / Word / Excel / صور)',
                        ),
                      ),
                      if (_uploadStatus.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            _uploadStatus,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF81C784), fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
                    ),
                  ),
                Expanded(
                  child: _files.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد مستندات مرفوعة بعد.\nارفع ملفاتك لتبدأ.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _files.length,
                          itemBuilder: (context, index) {
                            final f = _files[index];
                            final isIndexed = f.status == 'indexed';
                            return Card(
                              color: const Color(0xFF141A2A),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: Icon(
                                  isIndexed
                                      ? Icons.check_circle
                                      : Icons.sync,
                                  color: isIndexed
                                      ? const Color(0xFF81C784)
                                      : Colors.orangeAccent,
                                ),
                                title: Text(f.filename,
                                    style: const TextStyle(color: Colors.white)),
                                subtitle: Text(
                                  isIndexed
                                      ? (f.progress.isEmpty ? 'جاهز' : f.progress)
                                      : 'قيد المعالجة... ${f.progress}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: isIndexed ? () => _viewContent(f) : null,
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
    );
  }
}

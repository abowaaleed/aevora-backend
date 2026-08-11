import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';

class DocumentManagerScreen extends StatefulWidget {
  const DocumentManagerScreen({super.key});

  @override
  State<DocumentManagerScreen> createState() => _DocumentManagerScreenState();
}

class _DocumentManagerScreenState extends State<DocumentManagerScreen> {
  List<dynamic> _files = [];
  bool _isLoading = false;
  bool _isUploading = false;
  String? _uploadingFileName;
  Directory? _localDir;
  Set<String> _localFileNames = {};

  static const Color _greenPrimary = Color(0xFF4CAF50);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _fetchFiles();
    await _loadLocalNames();
    unawaited(_syncLocalToCloud());
  }

  // Persistent folder inside the app's Documents directory (backed up on
  // iOS), so uploaded files stay on the phone even if the cloud storage resets.
  Future<Directory> _getLocalDir() async {
    if (_localDir != null) return _localDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/evora_files');
    if (!await dir.exists()) await dir.create(recursive: true);
    _localDir = dir;
    return dir;
  }

  Future<void> _saveLocalCopy(PlatformFile file) async {
    try {
      final dir = await _getLocalDir();
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      await File('${dir.path}/${file.name}').writeAsBytes(bytes, flush: true);
      setState(() => _localFileNames.add(file.name));
    } catch (e) {
      debugPrint('Failed to save local copy of ${file.name}: $e');
    }
  }

  Future<void> _loadLocalNames() async {
    try {
      final dir = await _getLocalDir();
      final names = dir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toSet();
      if (mounted) setState(() => _localFileNames = names);
    } catch (e) {
      debugPrint('Error listing local files: $e');
    }
  }

  Future<void> _deleteLocalCopy(String filename) async {
    try {
      final dir = await _getLocalDir();
      final f = File('${dir.path}/$filename');
      if (await f.exists()) await f.delete();
      setState(() => _localFileNames.remove(filename));
    } catch (e) {
      debugPrint('Failed to delete local copy of $filename: $e');
    }
  }

  // Re-uploads any locally saved file missing from the cloud, so documents
  // survive storage resets on the free Render plan.
  Future<void> _syncLocalToCloud() async {
    try {
      final cloudNames = _files
          .map((f) => f['filename'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toSet();
      final dir = await _getLocalDir();
      final localFiles = dir.listSync().whereType<File>().toList();
      final missing =
          localFiles.where((f) => !cloudNames.contains(f.uri.pathSegments.last)).toList();
      if (missing.isEmpty) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('جارِ استعادة ${missing.length} ملف من جهازك...')),
        );
      }
      await _wakeBackend();
      var restored = 0;
      for (final f in missing) {
        try {
          final res = await _uploadWithRetry(f.uri.pathSegments.last, null, f.path);
          if (res.statusCode == 200) restored++;
        } catch (e) {
          debugPrint('Restore failed for ${f.uri.pathSegments.last}: $e');
        }
      }
      if (restored > 0) {
        await _fetchFiles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم استعادة $restored ملف من جهازك')),
          );
        }
      }
    } catch (e) {
      debugPrint('Local sync error: $e');
    }
  }

  Future<void> _fetchFiles() async {
    setState(() => _isLoading = true);
    try {
      final res = await http
          .get(Uri.parse('$backendUrl/rag/files'))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        setState(() => _files = jsonDecode(res.body));
      }
    } catch (e) {
      debugPrint("Error fetching files: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Wakes a cold Render free instance before uploading, so the first upload
  // doesn't hit a 502 while the instance is spinning up.
  Future<void> _wakeBackend() async {
    try {
      await http
          .get(Uri.parse('$backendUrl/health/'))
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  // Sends the upload request with a generous timeout and retries transient
  // failures (502 from a cold instance / network blips). The multipart request
  // is rebuilt on every attempt because its stream can only be sent once.
  Future<http.StreamedResponse> _uploadWithRetry(
    String filename,
    Uint8List? bytes,
    String? path,
  ) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final request = http.MultipartRequest('POST', Uri.parse('$backendUrl/rag/upload'));
        if (bytes != null) {
          request.files.add(http.MultipartFile.fromBytes('files', bytes, filename: filename));
        } else if (path != null) {
          request.files.add(await http.MultipartFile.fromPath('files', path, filename: filename));
        }
        final res = await request.send().timeout(const Duration(minutes: 3));
        if (res.statusCode < 500) return res;
        debugPrint('Upload attempt $attempt failed (${res.statusCode}), retrying...');
      } catch (e) {
        debugPrint('Upload attempt $attempt error: $e');
        if (attempt == maxAttempts) rethrow;
      }
      await Future.delayed(Duration(seconds: 2 * attempt));
    }
    throw Exception('Upload failed after $maxAttempts attempts');
  }

  Future<void> _pickAndUploadFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'pdf', 'docx', 'xlsx', 'csv', 'txt',
        'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'heic', 'heif',
      ],
    );

    if (result != null && result.files.isNotEmpty) {
      await _wakeBackend();
      for (var file in result.files) {
        setState(() {
          _isUploading = true;
          _uploadingFileName = file.name;
        });
        try {
          await _saveLocalCopy(file);
          final response = await _uploadWithRetry(file.name, file.bytes, file.path);

          if (response.statusCode == 200) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تم رفع ${file.name}. جاري المعالجة...')),
              );
            }
          } else {
            final errorBody = await response.stream.bytesToString();
            throw Exception('Upload failed (${response.statusCode}): $errorBody');
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('خطأ في رفع $file.name: $e'),
                duration: const Duration(seconds: 5),
                action: SnackBarAction(label: 'إعادة المحاولة', onPressed: _pickAndUploadFiles),
              ),
            );
          }
        }
      }
      setState(() {
        _isUploading = false;
        _uploadingFileName = null;
      });
      await _loadLocalNames();
      _fetchFiles();
    }
  }

  Future<void> _viewFileContent(String filename) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: _greenPrimary)),
    );

    try {
      final res = await http.get(Uri.parse('$backendUrl/rag/files/${Uri.encodeComponent(filename)}/content'));
      if (mounted) Navigator.of(context).pop();

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final content = data['content'] as String;
        final length = data['length'] as int;

        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: const Color(0xFF0D1424),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              filename,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$length حرف مستخرج',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        content,
                        style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        final detail = res.statusCode == 400 ? 'لم تتم المعالجة بعد' : 'خطأ في تحميل المحتوى';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$filename: $detail')));
        }
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  Future<void> _deleteFile(String filename) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF131A2B),
        title: const Text('حذف المستند', style: TextStyle(color: Colors.white)),
        content: Text('إزالة "$filename" وجميع بياناته المفهرسة؟', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await http.delete(Uri.parse('$backendUrl/rag/files/${Uri.encodeComponent(filename)}'));
        await _deleteLocalCopy(filename);
        _fetchFiles();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحذف: $e')));
        }
      }
    }
  }

  Future<void> _openOriginalFile(String filename) async {
    final url = Uri.parse(getFileUrl(filename));
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الملف في المتصفح')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'المستندات',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ارفع ملفات PDF أو Word أو جداول البيانات أو الصور — تُحفظ على جهازك وتُستعاد تلقائياً',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            if (_isUploading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const LinearProgressIndicator(backgroundColor: Colors.white12),
                    const SizedBox(height: 8),
                    Text(
                      'جاري رفع ${_uploadingFileName ?? "..."}...',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _greenPrimary))
                  : _files.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.description_outlined, size: 64, color: Colors.white24),
                              const SizedBox(height: 16),
                              const Text(
                                'لا توجد مستندات بعد',
                                style: TextStyle(color: Colors.white54, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'ارفع ملفات لبناء قاعدة معرفة ايفورا — وستبقى محفوظة على جهازك',
                                style: TextStyle(color: Colors.white30, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchFiles,
                          color: _greenPrimary,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _files.length,
                            itemBuilder: (context, index) {
                              final file = _files[index];
                              final status = file['status'] ?? 'unknown';
                              final progress = file['progress'] ?? '';
                              final filename = file['filename'] ?? 'Unknown';

                              IconData icon;
                              Color color;
                              switch (status) {
                                case 'indexed':
                                  icon = Icons.check_circle_outline_rounded;
                                  color = _greenPrimary;
                                  break;
                                case 'processing':
                                  icon = Icons.sync_rounded;
                                  color = Colors.blueAccent;
                                  break;
                                case 'failed':
                                  icon = Icons.error_outline_rounded;
                                  color = Colors.redAccent;
                                  break;
                                default:
                                  icon = Icons.access_time_rounded;
                                  color = Colors.amberAccent;
                              }

                              final canView = status == 'indexed';

                              return Card(
                                color: const Color(0xFF131A2B),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                margin: const EdgeInsets.only(bottom: 10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: canView ? () => _viewFileContent(filename) : null,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Icon(icon, color: color, size: 28),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                filename,
                                                style: TextStyle(
                                                  color: canView ? Colors.white : Colors.white70,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                progress.isNotEmpty ? progress : status.toUpperCase(),
                                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                                              ),
                                              if (_localFileNames.contains(filename)) ...[
                                                const SizedBox(height: 4),
                                                const Row(
                                                  children: [
                                                    Icon(Icons.phone_iphone_rounded, size: 12, color: Colors.white30),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'محفوظ على جهازك',
                                                      style: TextStyle(color: Colors.white30, fontSize: 11),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (status == 'processing')
                                          const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                                          ),
                                        if (canView) ...[
                                          IconButton(
                                            icon: const Icon(Icons.open_in_browser_rounded, color: Colors.white38, size: 20),
                                            onPressed: () => _openOriginalFile(filename),
                                            tooltip: 'فتح الملف الأصلي',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.visibility_outlined, color: Colors.white38, size: 20),
                                            onPressed: () => _viewFileContent(filename),
                                            tooltip: 'عرض المحتوى',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                                            onPressed: () => _deleteFile(filename),
                                            tooltip: 'حذف',
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _pickAndUploadFiles,
        backgroundColor: _greenPrimary,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('رفع'),
      ),
    );
  }
}

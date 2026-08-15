import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../client/client_plan.dart';
import '../client/client_upload.dart';
import '../screens/subscription_screen.dart';

/// رفع ملفات عبر نافذة تقدم واحدة:
/// 1) فحص حدود الخطة (الحجم/العدد/المساحة) — عند تجاوزها تُفتح نافذة ترقية.
/// 2) عرض شريط تقدم حي أثناء القراءة والاستخراج والفهرسة.
/// 3) إغلاق النافذة تلقائياً وإرجاع النتيجة للعرض.
///
/// يُرجع null إن مُنع الرفع بالحدود (وقد فُتحت نافذة الترقي)،
/// وإلا يعيد [UploadResult] بالنتيجة الكاملة.
Future<UploadResult?> showUploadFlow(
  BuildContext context, {
  required List<PlatformFile> files,
  required PlanState plan,
}) async {
  if (files.isEmpty) return const UploadResult(uploaded: 0, failed: 0, errors: []);

  final blockMessage = await checkUploadLimits(plan: plan, files: files);
  if (blockMessage != null) {
    if (context.mounted) {
      await _showUpgradePrompt(context, blockMessage, plan);
    }
    return null;
  }

  if (!context.mounted) return null;

  final progress = ValueNotifier<UploadProgress>(UploadProgress(
    fileIndex: 0,
    fileCount: files.length,
    filename: '',
    stage: 'جارٍ التحضير...',
    fraction: 0,
  ));

  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UploadProgressDialog(progress: progress),
  ));

  UploadResult result;
  try {
    result = await uploadAndIndexFiles(files: files, onProgress: (p) {
      progress.value = p;
    });
  } catch (e) {
    result = UploadResult(
      uploaded: 0,
      failed: 1,
      errors: ['فشل الرفع: $e'],
    );
  }
  progress.value = UploadProgress(
    fileIndex: files.length,
    fileCount: files.length,
    filename: '',
    stage: 'اكتمل الرفع',
    fraction: 1,
    done: true,
  );
  return result;
}

/// نافذة «الحد ممنوع» مع زر ترقية (للمجانية) أو تنبيه بسيط (للمدفوعة).
Future<void> _showUpgradePrompt(
  BuildContext context,
  String message,
  PlanState plan,
) async {
  final canUpgrade = !plan.isPremium;
  final goUpgrade = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF141A2A),
      title: Row(
        children: [
          const Icon(Icons.folder_off_outlined, color: Colors.orangeAccent),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('حد الخطة',
                style: TextStyle(color: Colors.white, fontSize: 17)),
          ),
        ],
      ),
      content: Text(
        message,
        textAlign: TextAlign.right,
        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.7),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء'),
        ),
        if (canUpgrade)
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.workspace_premium_outlined, size: 18),
            label: const Text('ترقية'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('حسناً'),
          ),
      ],
    ),
  );
  if (goUpgrade == true && context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
    );
  }
}

/// نافذة التقدم نفسها: تُغلق ذاتياً عند وصول [UploadProgress.done].
class _UploadProgressDialog extends StatefulWidget {
  final ValueNotifier<UploadProgress> progress;

  const _UploadProgressDialog({required this.progress});

  @override
  State<_UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<_UploadProgressDialog> {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_onProgress);
  }

  @override
  void dispose() {
    widget.progress.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    if (!mounted) return;
    setState(() {});
    final p = widget.progress.value;
    if (p.done && !_closing) {
      _closing = true;
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress.value;
    final progressValue = p.fraction.clamp(0.0, 1.0);
    return PopScope(
      canPop: p.done,
      child: Dialog(
        backgroundColor: const Color(0xFF141A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.upload_file_rounded, color: Color(0xFF4CAF50)),
                  SizedBox(width: 10),
                  Text(
                    'رفع المستندات',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (p.filename.isNotEmpty)
                Text(
                  p.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progressValue,
                minHeight: 8,
                borderRadius: BorderRadius.circular(6),
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF4CAF50)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.stage,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                  ),
                  if (p.fileCount > 1)
                    Text(
                      '${p.fileIndex} / ${p.fileCount}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'لا تغلق الصفحة أثناء الرفع — الملفات تُقرأ وتُفهرس محلياً على جهازك.',
                style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

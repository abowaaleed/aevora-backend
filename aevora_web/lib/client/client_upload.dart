import 'dart:async';

import 'package:file_picker/file_picker.dart';

import 'client_plan.dart';
import 'client_rag.dart';
import 'client_storage.dart';
import 'client_sync.dart';

/// تقدم رفع مجموعة ملفات — يُمرَّر للواجهة لتحديث شريط التقدم.
class UploadProgress {
  final int fileIndex; // يبدأ من 1
  final int fileCount;
  final String filename;
  final String stage;
  final double fraction; // 0..1 إجمالي كل الملفات
  final bool done;

  const UploadProgress({
    required this.fileIndex,
    required this.fileCount,
    required this.filename,
    required this.stage,
    required this.fraction,
    this.done = false,
  });
}

/// نتيجة رفع مجموعة ملفات (عدد الناجح والفاشل وأسباب الفشل).
class UploadResult {
  final int uploaded;
  final int failed;
  final List<String> errors;

  const UploadResult({
    required this.uploaded,
    required this.failed,
    required this.errors,
  });
}

/// استثناء خاص بحجب الرفع بسبب حدود الخطة.
class UploadBlockedException implements Exception {
  final String message;
  const UploadBlockedException(this.message);
}

String _fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes بايت';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} ك.ب';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} ج.ب';
}

String formatBytes(int bytes) => _fmtBytes(bytes);

/// ملخص الاستهلاك الحالي للمستندات (عدد + مساحة) لعرضه في الواجهات.
Future<Map<String, dynamic>> documentUsageSummary() async {
  var count = 0;
  var bytes = 0;
  try {
    for (final f in await LocalDb.listFiles()) {
      count++;
      bytes += (f['size'] as num?)?.toInt() ?? 0;
    }
  } catch (_) {}
  return {'count': count, 'bytes': bytes};
}

/// فحص حدود الخطة قبل الرفع. يرجع رسالة عربية إن كان الرفع ممنوعاً،
/// أو null إن كان كل شيء مسموحاً. يُستدعى قبل قراءة الملفات نفسها.
Future<String?> checkUploadLimits({
  required PlanState plan,
  required List<PlatformFile> files,
}) async {
  final quota = quotaForPlan(plan);
  if (files.isEmpty) return null;
  final existing = await LocalDb.listFiles();
  final existingNames = {
    for (final f in existing) (f['name'] ?? '').toString(),
  };

  var newCount = 0;
  var addBytes = 0;
  for (final f in files) {
    final size = await f.length();
    if (size > quota.maxFileSizeBytes) {
      return 'الملف «${f.name}» حجمه ${_fmtBytes(size)} ويتجاوز الحد المسموح '
          '(${_fmtBytes(quota.maxFileSizeBytes)}) في خطتك الحالية.'
          '${plan.isPremium ? '' : ' رقِّ خطتك لرفع ملفات أكبر.'}';
    }
    if (!existingNames.contains(f.name)) newCount++;
    addBytes += size;
  }

  if (existing.length + newCount > quota.maxFiles) {
    return 'بلغت الحد الأقصى لعدد المستندات في خطتك (${quota.maxFiles}). '
        '${plan.isPremium ? 'احذف مستندات قديمة لإفساح المجال.' : 'رقِّ خطتك لرفع حتى 300 مستند.'}';
  }

  var usedBytes = 0;
  for (final f in existing) {
    usedBytes += (f['size'] as num?)?.toInt() ?? 0;
  }
  if (usedBytes + addBytes > quota.maxStorageBytes) {
    return 'تجاوزت مساحة التخزين المتاحة في خطتك '
        '(${_fmtBytes(quota.maxStorageBytes)}). '
        '${plan.isPremium ? 'احذف مستندات قديمة لتوفير مساحة.' : 'رقِّ خطتك لمساحة تخزين 1 ج.ب.'}';
  }
  return null;
}

/// رفع وفهرسة الملفات مع إبلاغ التقدم لكل مرحلة (قراءة ← استخراج ← فهرسة).
Future<UploadResult> uploadAndIndexFiles({
  required List<PlatformFile> files,
  required void Function(UploadProgress progress) onProgress,
}) async {
  var uploaded = 0;
  final errors = <String>[];
  final total = files.length;
  var doneBase = 0.0;

  for (var i = 0; i < total; i++) {
    final f = files[i];
    final fileFraction = 1.0 / total;
    try {
      onProgress(UploadProgress(
        fileIndex: i + 1,
        fileCount: total,
        filename: f.name,
        stage: 'قراءة الملف...',
        fraction: doneBase,
      ));
      // دع الواجهة ترسم «قراءة الملف...» قبل قراءة الملف الكبير.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('تعذّرت قراءة الملف «${f.name}» — جرّب رفعه مرة أخرى.');
      }
      await indexLocalFile(
        f.name,
        bytes,
        onProgress: (frac, stage) {
          onProgress(UploadProgress(
            fileIndex: i + 1,
            fileCount: total,
            filename: f.name,
            stage: stage,
            fraction: doneBase + fileFraction * frac,
          ));
        },
      );
      uploaded++;
      SyncStore.schedulePush();
    } catch (e) {
      errors.add('«${f.name}»: ${_friendlyUploadError(e)}');
    }
    doneBase += fileFraction;
  }
  return UploadResult(uploaded: uploaded, failed: errors.length, errors: errors);
}

/// تحويل أخطاء الرفع/الفهرسة إلى رسالة عربية مفهومة (بدون «Exception:»).
String _friendlyUploadError(Object e) {
  var s = e.toString();
  if (s.startsWith('Exception: ')) s = s.substring(11);
  if (s.startsWith('Unsupported operation: ')) s = s.substring(24);
  return s.trim().isEmpty ? 'خطأ غير معروف' : s;
}

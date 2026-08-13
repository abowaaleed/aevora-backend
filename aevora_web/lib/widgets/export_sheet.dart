import 'package:flutter/material.dart';

import '../client/client_export.dart';

/// نافذة منبثقة لتصدير محادثة (مشاركة / تحميل / نسخ) مع نص ترويج ايفورا.
Future<void> showExportSheet(
  BuildContext context, {
  required String text,
  required String filename,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF141A2A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      void done(String msg) {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, textAlign: TextAlign.right),
            backgroundColor: const Color(0xFF1D3A1D),
          ),
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'تصدير المحادثة مع ترويج ايفورا',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'سيُرفق تلقائياً نص دعوة لتحميل واستخدام ايفورا مع المحادثة.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded, color: Color(0xFF4CAF50)),
              title: const Text('مشاركة', style: TextStyle(color: Colors.white)),
              subtitle: const Text('واتساب / تيليجرام / البريد...',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () async {
                final ok = await tryShareText(text, title: 'محادثة مع ايفورا');
                if (ok) {
                  if (ctx.mounted) Navigator.pop(ctx);
                } else {
                  done('المشاركة غير مدعومة على هذا المتصفح — استخدم التحميل أو النسخ.');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: Color(0xFF4CAF50)),
              title: const Text('تحميل ملف نصي', style: TextStyle(color: Colors.white)),
              subtitle: const Text('ملف .txt يمكن لصقه في Word', style: TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () {
                downloadTextFile(text, filename);
                done('تم تنزيل الملف.');
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_copy_rounded, color: Color(0xFF4CAF50)),
              title: const Text('نسخ إلى الحافظة', style: TextStyle(color: Colors.white)),
              subtitle: const Text('الصقها أينما شئت', style: TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () async {
                await copyTextToClipboard(text);
                done('تم نسخ المحادثة.');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

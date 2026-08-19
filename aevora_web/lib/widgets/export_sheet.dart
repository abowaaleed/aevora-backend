import 'package:flutter/material.dart';

import '../client/client_export.dart';
import '../client/client_share.dart';

/// نافذة مشاركة المحادثة: واتساب، تيليجرام، البريد، نسخ.
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
      Future<void> go(Future<bool> Function() action, String okMsg) async {
        try {
          final ok = await action();
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          if (!ok) {
            await copyTextToClipboard(text);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'تعذّر فتح التطبيق — نُسخت المحادثة إلى الحافظة.',
                    textAlign: TextAlign.right,
                  ),
                ),
              );
            }
          } else if (okMsg.isNotEmpty && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(okMsg, textAlign: TextAlign.right),
                backgroundColor: const Color(0xFF1D3A1D),
              ),
            );
          }
        } catch (_) {
          if (ctx.mounted) Navigator.pop(ctx);
        }
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'مشاركة المحادثة',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'أرسل المحادثة عبر واتساب أو تيليجرام أو البريد.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
              title: const Text('واتساب', style: TextStyle(color: Colors.white)),
              onTap: () => go(() => shareViaWhatsApp(text), ''),
            ),
            ListTile(
              leading: const Icon(Icons.send_rounded, color: Color(0xFF2AABEE)),
              title: const Text('تيليجرام', style: TextStyle(color: Colors.white)),
              onTap: () => go(() => shareViaTelegram(text), ''),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline_rounded, color: Color(0xFF4CAF50)),
              title: const Text('البريد الإلكتروني',
                  style: TextStyle(color: Colors.white)),
              onTap: () => go(() => shareViaEmail(text), ''),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy_rounded, color: Color(0xFF4CAF50)),
              title: const Text('نسخ إلى الحافظة',
                  style: TextStyle(color: Colors.white)),
              onTap: () async {
                await copyTextToClipboard(text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم نسخ المحادثة.', textAlign: TextAlign.right),
                      backgroundColor: Color(0xFF1D3A1D),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: Color(0xFF4CAF50)),
              title: const Text('تحميل ملف نصي',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                try {
                  downloadTextFile(text, filename);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم تنزيل الملف.', textAlign: TextAlign.right),
                      backgroundColor: Color(0xFF1D3A1D),
                    ),
                  );
                } catch (e) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$e', textAlign: TextAlign.right)),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

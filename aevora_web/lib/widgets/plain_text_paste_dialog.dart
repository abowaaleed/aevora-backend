import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// نافذة «لصق نص طويل» — تُلصق محتوى الحافظة كـ **نص عادي** بدلاً من صورة.
///
/// في المتصفح: عند لصق محتوى منسّق من Word (غالباً يحوي صورة/نسخة مرئية)،
/// تعترض هذه النافذة حدث `paste` وتقرأ `text/plain` من الحافظة مباشرة
/// وتدرجه في الحقل — فتنتهي المشكلة نهائياً.
class PlainTextPasteDialog extends StatefulWidget {
  const PlainTextPasteDialog({super.key});

  @override
  State<PlainTextPasteDialog> createState() => _PlainTextPasteDialogState();
}

class _PlainTextPasteDialogState extends State<PlainTextPasteDialog> {
  static const _green = Color(0xFF4CAF50);
  static const _bg = Color(0xFF070B14);
  static const _card = Color(0xFF141A2A);

  final TextEditingController _controller = TextEditingController();
  String _status = '';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      web.window.addEventListener('paste', _onPaste.toJS, true.toJS);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      web.window.removeEventListener('paste', _onPaste.toJS, true.toJS);
    }
    _controller.dispose();
    super.dispose();
  }

  void _onPaste(web.Event e) {
    if (!mounted) return;
    final clipboard = (e as web.ClipboardEvent).clipboardData;
    final text = clipboard?.getData('text/plain') ?? '';
    if (text.trim().isEmpty) {
      e.preventDefault();
      e.stopPropagation();
      setState(() {
        _status =
            'الحافظة تحتوي صورة بدون نص. في Word: حدد النص واضغط Ctrl+C مباشرة '
            '(وليس «نسخ كصورة»)، أو الصق أولاً في المفكرة ثم انسخ من هناك.';
      });
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    setState(() => _status = '');
    final c = _controller;
    final base = c.selection.baseOffset;
    final extent = c.selection.extentOffset;
    final start = base < extent ? base : extent;
    final end = base < extent ? extent : base;
    final newText = c.text.replaceRange(start, end, text);
    c.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _bg,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.content_paste_go_rounded, color: _green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('لصق نص من Word',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'الصق النص هنا (⌘V / Ctrl+V) — سيُعالج كنص عادي وليس صورة.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.6),
                  decoration: InputDecoration(
                    hintText: 'الصق هنا...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: _card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(_status, style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء',
                        style: TextStyle(color: Colors.white54)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, _controller.text.trim()),
                    style: FilledButton.styleFrom(backgroundColor: _green),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('إرسال النص'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

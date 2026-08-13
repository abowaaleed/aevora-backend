import 'package:flutter/material.dart';

/// زر "المتابعة بحساب Google" برمز G الرسمي بألوان Google الأربعة.
class GoogleGButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;

  const GoogleGButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        disabledBackgroundColor: Colors.white70,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: const _GoogleG(size: 20),
      label: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _GoogleG extends StatelessWidget {
  final double size;
  const _GoogleG({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

/// شعار G من مسارات SVG الرسمية (viewBox 48×48).
class _GoogleGPainter extends CustomPainter {
  static const _paths = <(String, Color)>[
    (
      'M45.12 24.5c0-2.34-.2-3.96-.64-5.68H24v10.55h12.13c-.26 1.55-1.55 4.02-4.47 5.66l-.04.22 6.49 5.02.45.05C42.87 35.95 45.12 30.7 45.12 24.5',
      Color(0xFF4285F4),
    ),
    (
      'M24 46c5.94 0 10.92-1.96 14.56-5.33L29.62 35.7c-1.98 1.38-4.62 2.35-8.14 2.35-6.2 0-11.47-4.1-13.35-9.62l-.27.02-6.76 5.23-.09.25C7.47 39.77 15.07 46 24 46',
      Color(0xFF34A853),
    ),
    (
      'M10.53 28.43C10.13 27.21 9.9 25.91 9.9 24.5s.23-2.71.63-3.93l-.05-.27-6.85-5.32-.22.11C1.5 17.49.5 20.68.5 24.5s1 7.01 2.91 9.41l7.12-5.48',
      Color(0xFFFBBC05),
    ),
    (
      'M24 9.92c4.4 0 7.36 1.9 9.05 3.49l6.6-6.44C34.9 3.74 29.92 2 24 2 15.07 2 7.47 8.23 3.54 15.41l6.99 5.43c1.88-5.52 7.15-9.92 13.35-9.92',
      Color(0xFFEA4335),
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final (d, color) in _paths) {
      paint.color = color;
      canvas.drawPath(_svgPath(d, size.width / 48.0), paint);
    }
  }

  /// محلل بسيط لمسارات SVG يدعم: M/m L/l H/h V/v C/c S/s Z/z.
  static Path _svgPath(String d, double scale) {
    final p = Path();
    final tokens = RegExp(r'([MmLlHhVvCcSsZz])|(-?[\d.]+)')
        .allMatches(d)
        .map((m) => m.group(0)!)
        .toList();
    var i = 0;
    var x = 0.0, y = 0.0;
    var sx = 0.0, sy = 0.0;
    var lastCmd = '';
    var lastControlX = 0.0, lastControlY = 0.0;
    final hasCtl = [false];

    List<double> read(int n) {
      final out = <double>[];
      while (out.length < n && i < tokens.length) {
        if (RegExp(r'^-?[\d.]+$').hasMatch(tokens[i])) {
          out.add(double.parse(tokens[i]));
        }
        i++;
      }
      return out;
    }

    while (i < tokens.length) {
      var cmd = tokens[i];
      if (!RegExp(r'^[MmLlHhVvCcSsZz]$').hasMatch(cmd)) {
        cmd = lastCmd; // أمر ضمني (تكرار)
      } else {
        i++;
      }
      if (cmd.isEmpty) break;
      final isRel = cmd == cmd.toLowerCase();
      final u = cmd.toUpperCase();

      if (u == 'M') {
        final a = read(2);
        x = isRel ? x + a[0] : a[0];
        y = isRel ? y + a[1] : a[1];
        sx = x; sy = y;
        p.moveTo(x * scale, y * scale);
        lastCmd = 'M';
        hasCtl[0] = false;
      } else if (u == 'L') {
        final a = read(2);
        x = isRel ? x + a[0] : a[0];
        y = isRel ? y + a[1] : a[1];
        p.lineTo(x * scale, y * scale);
        lastCmd = 'L';
        hasCtl[0] = false;
      } else if (u == 'H') {
        final a = read(1);
        x = isRel ? x + a[0] : a[0];
        p.lineTo(x * scale, y * scale);
        lastCmd = 'H';
        hasCtl[0] = false;
      } else if (u == 'V') {
        final a = read(1);
        y = isRel ? y + a[0] : a[0];
        p.lineTo(x * scale, y * scale);
        lastCmd = 'V';
        hasCtl[0] = false;
      } else if (u == 'C') {
        final a = read(6);
        final x1 = isRel ? x + a[0] : a[0];
        final y1 = isRel ? y + a[1] : a[1];
        final x2 = isRel ? x + a[2] : a[2];
        final y2 = isRel ? y + a[3] : a[3];
        final x3 = isRel ? x + a[4] : a[4];
        final y3 = isRel ? y + a[5] : a[5];
        p.cubicTo(x1 * scale, y1 * scale, x2 * scale, y2 * scale,
            x3 * scale, y3 * scale);
        lastControlX = x2; lastControlY = y2;
        x = x3; y = y3;
        lastCmd = 'C';
        hasCtl[0] = true;
      } else if (u == 'S') {
        final a = read(4);
        var x1 = 0.0, y1 = 0.0;
        if (hasCtl[0]) {
          x1 = 2 * x - lastControlX;
          y1 = 2 * y - lastControlY;
        } else {
          x1 = x; y1 = y;
        }
        final x2 = isRel ? x + a[0] : a[0];
        final y2 = isRel ? y + a[1] : a[1];
        final x3 = isRel ? x + a[2] : a[2];
        final y3 = isRel ? y + a[3] : a[3];
        p.cubicTo(x1 * scale, y1 * scale, x2 * scale, y2 * scale,
            x3 * scale, y3 * scale);
        lastControlX = x2; lastControlY = y2;
        x = x3; y = y3;
        lastCmd = 'S';
        hasCtl[0] = true;
      } else if (u == 'Z') {
        p.close();
        x = sx; y = sy;
        lastCmd = 'Z';
        hasCtl[0] = false;
      }
    }
    return p;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

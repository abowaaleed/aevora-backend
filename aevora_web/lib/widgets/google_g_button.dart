import 'package:flutter/material.dart';

/// زر تسجيل الدخول بحساب Google بأسلوب التطبيقات العالمية:
/// خلفية بيضاء، شعار Google الملون، ونص واضح.
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
    return Material(
      color: Colors.white,
      elevation: enabled ? 1.5 : 0,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(24),
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFDADCE0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CustomPaint(painter: _GoogleGPainter()),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF3C4043),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// شعار Google الملون (أزرق/أحمر/أصفر/أخضر) برسم متجه بسيط.
class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final stroke = size.width * 0.18;
    final rect = Rect.fromCircle(center: c, radius: r - stroke / 2);

    void arc(Color color, double start, double sweep) {
      final p = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, sweep, false, p);
    }

    const blue = Color(0xFF4285F4);
    const red = Color(0xFFEA4335);
    const yellow = Color(0xFFFBBC05);
    const green = Color(0xFF34A853);

    arc(blue, -0.55, 1.85);
    arc(green, 1.25, 1.05);
    arc(yellow, 2.25, 0.85);
    arc(red, 3.1, 1.35);

    final bar = Paint()..color = blue;
    canvas.drawRect(
      Rect.fromLTWH(c.dx, c.dy - stroke / 2, r - stroke * 0.15, stroke),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

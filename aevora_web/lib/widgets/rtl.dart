import 'package:flutter/widgets.dart';

/// يفرض اتجاه النص من اليمين إلى اليسار على محتواه، ليبقى العربي متناسقاً
/// مع الكلمات الإنجليزية والأرقام داخل النصوص والعدادات.
class Rtl extends StatelessWidget {
  final Widget child;
  const Rtl({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: TextDirection.rtl, child: child);
}

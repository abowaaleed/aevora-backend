import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// عند مغادرة/إخفاء الصفحة (تحويل تبويب/إغلاق) نرفع أي تعديل لم يُرفع بعد
/// حتى لا يضيع عند التبديل بين الأجهزة.
void attachLifecycleFlush(void Function() onHidden) {
  web.window.addEventListener(
      'pagehide', ((web.Event e) => onHidden()).toJS);
  web.window.addEventListener(
      'visibilitychange',
      ((web.Event e) {
        if (web.document.visibilityState == 'hidden') onHidden();
      }).toJS);
}

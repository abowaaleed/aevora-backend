{{flutter_js}}
{{flutter_build_config}}

// إلغاء أي Service Worker قديم فوراً: هو السبب الأرجح لبقاء التطبيق على نسخة
// قديمة (تستبدل المحادثة المحلية عند السحب بدل دمجها) رغم نشر الإصلاحات.
// بدون Service Worker يُجلب كل حمل جديد آخر بناء مباشرةً من GitHub Pages.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then(function (regs) {
    for (const reg of regs) {
      reg.unregister();
    }
  });
}

_flutter.loader.load({});

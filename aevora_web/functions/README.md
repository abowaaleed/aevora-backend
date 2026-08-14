# وظائف الدفع (Cloud Functions) لتطبيق ايفورا

هذه الوظائف تُنشر على Firebase Cloud Functions وتتكلم مع بوابة **Tap** (الموصى بها
لدعم mada / Apple Pay / STC Pay في السعودية والخليج)، مع إمكانية التبديل إلى
Moyasar أو Stripe بتعديل `GATEWAY` في `src/index.ts`.

## ماذا تفعل؟

| الوظيفة | الوصف |
|---|---|
| `createCheckout` | تُنشئ جلسة دفع عبر Tap وتعرض للمستخدم رابط صفحة الدفع، وتسجّل نية الاشتراك `pending` |
| `handleWebhook` | تستقبل تأكيد الدفع من Tap وتكتب الخطة `active` على مستند المستخدم في Firestore |
| `cancelSubscription` | تُلغي الاشتراك (تُوقف الامتيازات) |

التطبيق يقرأ حالة الخطة من `users/{uid}/plan` تلقائياً عبر `PlanStore`
(لا يحتاج أي إعادة بناء — التفعيل فوري بعد الدفع).

## خطوات التفعيل

1. أنشئ مشروع Firebase إن لم يكن موجوداً واربط المجلد الجذري:
   ```bash
   firebase init functions
   ```
   اختر `functions/` الحالي عند السؤال.

2. أنشئ حساب تاجر لدى Tap (https://tap.company) واحصل على المفتاح السري
   وأضف نقطة webhook إلى: `https://us-central1-<projectId>.cloudfunctions.net/handleWebhook`
   مع `x-tap-token` لتفعيل التحقق.

3. ضع المتغيرات السرية (لا تُكشف أبداً في التطبيق):
   ```bash
   firebase functions:secrets:set TAP_SECRET_KEY
   firebase functions:secrets:set TAP_WEBHOOK_TOKEN
   ```

4. حدّث الأسعار/العملة في `PRICES` عند الحاجة، ثم انشر:
   ```bash
   cd functions
   npm install
   npm run deploy
   ```

5. في التطبيق ضع المفتاح العام في `lib/client/payment_config.dart`
   (`publishableKey` و`functionsBaseUrl`) — عندها تُفعَّل أزرار الاشتراك تلقائياً.

## ملاحظة قانونية

الدفع الإلكتروني بالسعودية يتطلب سجلاً تجارياً وتفعيل الضريبة (VAT 15%).
تأكد من توافق الأسعار المعروضة مع فاتورة الدفع النهائية.

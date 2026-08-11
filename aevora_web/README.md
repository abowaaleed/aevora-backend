# ايفورا ويب — النسخة العامة (بمفاتيح المستخدم)

تطبيق ويب يعمل بأي متصفح. كل مستخدم يضع **مفاتيحه الخاصة** (Gemini و/أو Groq)
وإيميله في صفحة الإعدادات، فيستهلك الحصة المجانية الشخصية له دون المساس بحصة خادمك الخاص.

المفاتيح تُحفظ في متصفح المستخدم (localStorage) فقط، ولا تُرسل إلا إلى خادم ايفورا العام
داخل رؤوس الطلبات ليستعملها نيابة عنه — بلا أي تخزين أو تسجيل على الخادم.
هوية المستخدم (user_id) مشتقة من مفاتيحه، فتتوزع بياناته ومحادثاته ومستنداته في مجلد معزول خاص به.

## البنية

- `aevora_web/` — واجهة Flutter (ويب فقط).
- خادم عام جديد على Render (`evora-backend-public`) يشتغل بوضع `PUBLIC_MODE=true`
  ويرفض أي طلب بلا مفتاح، ولا يستعمل مفاتيح الخادم إطلاقاً.

## النشر

### 1) الخادم العام

في `render.yaml` أضيفت الخدمة `evora-backend-public` مع `PUBLIC_MODE=true`.
من لوحة Render: **New > Blueprint** واختر المستودع — ستُنشأ الخدمتان معاً.
بعد الإنشاء خذ رابط الخدمة، مثال: `https://evora-backend-public.onrender.com`

> ملاحظة: لا تضع `GEMINI_API_KEY`/`GROQ_API_KEY` في الخدمة العامة إطلاقاً —
> لو وُجدت على الخادم ستُهمل تلقائياً بفضل `PUBLIC_MODE`.

### 2) الواجهة

```bash
cd aevora_web
flutter pub get
flutter build web --release --dart-define=API_BASE=https://<public-backend>.onrender.com
```

المخرجات في `build/web/` — انشر هذا المجلد على أي استضافة ثابتة (Render Static Site، GitHub Pages، Netlify...).

### 3) التجربة محلياً

```bash
# 1) شغّل الخادم العام
cd backend
PUBLIC_MODE=true ./venv/bin/python -m uvicorn main:app --port 8000

# 2) شغّل الواجهة
cd aevora_web
flutter run -d chrome
```

## مفاتيح المستخدم

| الحقل | من أين تحصل عليه |
|---|---|
| Gemini | https://aistudio.google.com/apikey |
| Groq | https://console.groq.com/keys |

أدخل مفتاحاً واحداً على الأقل. عند فشل Gemini (حصّة/خطأ) ينتقل النظام تلقائياً إلى Groq.
الصوت: STT عبر Groq Whisper (أو مفتاح Gemini)، TTS عبر `edge-tts` المجاني على الخادم.

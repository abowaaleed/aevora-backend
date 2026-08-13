# ايفورا — دليل المعمارية الحديثة (Zero-Cost Architecture)

> هذا المستند يصف **المعمارية الكاملة** للتطبيق كما هي الآن، ويعمل أيضاً
> كبروميت جاهز تنسخه لأي أداة ذكاء اصطناعي لفهم المشروع والاستمرار في تطويره.

---

## 1. الفكرة الجوهرية

**ايفورا** تطبيق تعليمي ذكي لتعلم الإنجليزية، أُعيدت هندسته بالكامل ليعمل
**دون أي خادم خلفي** — واجهة Flutter ويب تُنشر كـ **Static/PWA** مجانية، وكل
الذكاء يحدث **داخل متصفح المستخدم**:

- لا خادم، لا قاعدة بيانات سحابية، لا تسجيل، لا اشتراكات.
- المستخدم يُدخل **مفاتيحه الخاصة** (BYOK: Bring Your Own Key) من Google Gemini و Groq.
- كل البيانات (محادثات، ملفات، ذاكرة المساعد، عدادات) محفوظة في **IndexedDB** بجهازه.
- التكلفة صفر تقريباً: الاستضافة مجانية (GitHub Pages)، والنماذج مجانية/رخيصة بمفاتيح المستخدم.

---

## 2. المبادئ التصميمية

| المبدأ | التنفيذ |
|---|---|
| لا خادم إطلاقاً | كل المكالمات تذهب من المتصفح مباشرة إلى مزودي النماذج (Gemini / Groq) |
| الخصوصية أولاً | المفاتيح والبيانات لا تغادر جهاز المستخدم أبداً (تُرسل المفاتيح لمزودها فقط) |
| البقاء بعد الإغلاق | تخزين IndexedDB محلي (لا يُمسح عند إغلاق المتصفح) |
| ربط بالجهاز لا بالحساب | البيانات ترتبط بالمتصفح/الجهاز — لا يوجد "حساب" عبر أجهزة |
| نشر مجاني | خرج Flutter web ثابت يُنشر على GitHub Pages |
| تجربة RTL | كل الواجهة عربية الاتجاه، مع شارات RLM عند النسخ/التصدير لـ Word |

---

## 3. بنية المشروع

المشروع الحالي النشط هو `aevora_web/` (المجلدات `backend/` و `frontend/`
قديمة ولا تُستخدم).

```
EnglishCompanion/
├── aevora_web/                  ← الواجهة الحالية (100% client-side)
│   ├── lib/
│   │   ├── main.dart            ← نقطة الدخول + التوجيه (keys → /shell)
│   │   ├── config.dart          ← KeySettings + AppStorage (localStorage)
│   │   ├── client/              ← طبقة العميل (بدون Flutter UI)
│   │   │   ├── client_storage.dart    ← قاعدة IndexedDB
│   │   │   ├── client_llm.dart        ← Gemini مباشرة (محادثة/تحليل)
│   │   │   ├── client_rag.dart        ← استخراج النصوص + بحث محلي
│   │   │   ├── client_voice.dart      ← TTS احترافي + STT (Whisper)
│   │   │   ├── client_companion.dart  ← ذاكرة المساعد ومهامه
│   │   │   ├── client_usage.dart      ← عدادات يومية محلية
│   │   │   └── client_export.dart     ← تصدير المحادثة مع ترويج
│   │   ├── screens/             ← شاشات التطبيق
│   │   │   ├── shell.dart             ← الإطار + شريط التبويبات السفلي
│   │   │   ├── chat_screen.dart       ← الدردشة (Gemini + مستندات)
│   │   │   ├── companion_screen.dart  ← المساعد الشخصي
│   │   │   ├── document_screen.dart   ← رفع وفهرسة المستندات محلياً
│   │   │   ├── memory_screen.dart     ← ذاكرة المساعد والملف الشخصي
│   │   │   ├── settings_screen.dart   ← المفاتيح + العدادات
│   │   │   └── key_setup_screen.dart  ← إدخال المفاتيح عند أول تشغيل
│   │   └── widgets/
│   │       ├── export_sheet.dart             ← نافذة تصدير المحادثة
│   │       └── plain_text_paste_dialog.dart  ← لصق نص عادي من Word
│   ├── test/client_rag_test.dart  ← اختبارات (تمر)
│   └── web/manifest.json          ← PWA manifest
├── README.md                   ← يشرح zero-cost والخصوصية
└── backend/, frontend/         ← قديمة — لا تُستخدم
```

---

## 4. الطبقات التقنية (client/)

### 4.1 التخزين المحلي — `client_storage.dart`
- قاعدة **IndexedDB** عبر `idb_shim` + `idbFactoryBrowser.open` (من `package:web`).
- مخازن (stores): `kv` (مفاتيح/قيم عامة) · `files` (بيانات الملفات) ·
  `blobs` (محتوى الملفات) · `chunks` (مقاطع الفهرسة).
- واجهة `LocalDb`: `kvGet/kvPut/kvGetValue/kvDelete` · `saveFileMeta/listFiles`
  · `saveFileBlob/fileBlob` · `saveChunks/deleteChunks`.
- يستخدم `Uint8ListBytes` (من `syncfusion_flutter_pdf`) لتخزين الملفات الثنائية.

### 4.2 النماذج اللغوية — `client_llm.dart`
- استدعاء مباشر لـ `https://generativelanguage.googleapis.com/v1beta` بمفتاح المستخدم.
- `geminiStreamChat` — محادثة **متدفقة SSE** (`:streamGenerateContent?alt=sse`) مع
  `systemInstruction` و`generationConfig`، وتستدعي `LocalUsage.recordGemini()`.
- `geminiChatSync` — نسخة غير متدفقة للتحليل الخلفي (استخراج الذاكرة…).
- **النموذج الافتراضي**: `gemini-3.6-flash` (GA — الاستبدال المعتمد للنموذج
  القديم `gemini-2.5-flash` الذي لم يعد متاحاً للمستخدمين الجدد).

### 4.3 الفهرسة والبحث المحلي — `client_rag.dart`
- `extractText` — استخراج النص من **PDF عبر Syncfusion** (`syncfusion_flutter_pdf`)
  ومن **TXT** (تشمل Tika/تحويلات بسيطة).
- `chunkText` — تقطيع بمقاطع 1200 حرف مع تداخل 150.
- `embedText` — متجهات **Hashing TF** محلية (256 بُعداً، بدون أي نموذج خارجي).
- `indexLocalFile` / `retrieveChunks` / `buildContextPrompt` —
  فهرسة الملف وحفظ المقاطع و`متجهاتها` في IndexedDB، ثم استرجاع أكثر المقاطع
  تشابهاً (جيب التمام) وبناء سياق يُلحق برسالة النظام في الدردشة.
- **لا يُرسل محتوى المستندات لأي مكان** — كل الفهرسة والاسترجاع داخل المتصفح.

### 4.4 الصوت — `client_voice.dart`
**النطق (TTS) — احترافي عبر Gemini:**
- `speakProfessional` + `geminiTextToSpeech` — نموذج
  `gemini-3.1-flash-tts-preview` (نفس مفتاح Gemini، صوت Neural طبيعي يدعم العربية).
- استدعاء `:generateContent` مع `responseModalities: ["AUDIO"]` و
  `speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName` (الافتراضي `Kore`).
- الرد يعود بصيغة `audio/L16;rate=24000` (PCM خام) → `_wrapPcmInWav` يبني رأس
  WAV (44 بايت) → `web.Blob` → `URL.createObjectURL` → `HTMLAudioElement.play()`.
- `speakSmart` — يفضّل الاحترافي، ويعود تلقائياً لصوت المتصفح (Web Speech) عند غياب المفتاح أو خطأ.
- `stopSpeaking` يوقف كلاً من `speechSynthesis` وعنصر الصوت.
- `speakText` (Web Speech API) — احتياطي مجاني بدون مفتاح (عربي/إنجليزي + بطيء).

**التعرف على الصوت (STT):**
- `groqTranscribe` — تسجيل WAV من المتصفح (مكتبة `record`) ثم إرساله مباشرة إلى
  `https://api.groq.com/openai/v1/audio/transcriptions` (نموذج `whisper-large-v3`)
  بمفتاح Groq → `LocalUsage.recordWhisper()`.

### 4.5 المساعد الشخصي — `client_companion.dart`
- `LocalCompanion.loadState` — يقرأ الحالة الكاملة: `profile` (الاسم/المستوى/
  الأهداف/المفردات/التصحيحات) · `memories` · `tasks` · `recent` (آخر المحادثة) · `proactive`.
- `streamReply` — رد متدفق مع سياق الذاكرة والملف الشخصي.
- `_analyze` — تحليل خلفي لكل تبادل (عبر `geminiChatSync`) لاستخراج: مهام،
  ذكريات، مفردات جديدة، تصحيحات لغوية → تُحفظ في IndexedDB.
- `maybeGenerateProactive` — مبادرة يومية (سؤال/اقتراح) بحد زمني.
- `addTask/toggleTask/deleteTask/reset` — إدارة المهام ومسح الذاكرة.

### 4.6 العدادات اليومية — `client_usage.dart`
- `LocalUsage.today()` — بنية `{date, gemini:{used,limit,remaining}, groq,
  stt_groq, companion}` محفوظة بمفتاح `usage_today`.
- تتصفّر تلقائياً عند تغيّر اليوم (تقارن التاريخ).
- حدود داخلية: `geminiLimit=1500` · `groqLimit=1000` · `whisperLimit=2000`
  (قيم افتراضية تقديرية قابلة للتعديل).

### 4.7 التصدير والترويج — `client_export.dart`
- `buildExportText` — يجمع المحادثة (أنت/ايفورا) + تاريخ + **نص ترويجي
  تلقائي** يدعو لتحميل ايفورا، ويسبق الأسطر بشارة `\u200F` (RLM) لعرض صحيح في Word.
- `tryShareText` — Web Share API عبر interop مخصص (`dart:js_interop`) للمشاركة
  في واتساب/تيليجرام… (يعود false إن كان غير مدعوم).
- `downloadTextFile` — تنزيل `.txt` عبر `data:` URI بلا خادم.
- `copyTextToClipboard` — نسخ إلى الحافظة.
- واجهة العرض: `widgets/export_sheet.dart` (مشاركة / تحميل / نسخ).

---

## 5. الشاشات والتدفق

1. **main.dart** → يقرأ `AppStorage.load()`؛ إن وُجدت مفاتيح انتقل لـ `/shell`
   وإلا `/keys` (شاشة إدخال المفاتيح).
2. **shell.dart** → إطار به 4 تبويبات: الدردشة · المساعد · المستندات · الإعدادات
   (مع روابط للذاكرة من الإعدادات).
3. **chat_screen.dart** — محادثة متدفقة مع Gemini + سياق RAG من المستندات +
   صوت (تسجيل/تفريغ/نطق/نطق بطيء) + لصق Word + زر **تصدير** أعلى الشاشة.
   - حقل الإدخال **متعدد الأسطر** (`multiline`، `minLines:1 maxLines:5`،
     `TextInputAction.newline`) — لا يخفي النص الطويل.
   - الرسائل تُحفظ تلقائياً بمفتاح `chat_messages`.
4. **companion_screen.dart** — مساعد يتذكر، مهام، ذكريات، مبادرة يومية.
   - الترويسة مكوّنة من سطرين: (صورة + عنوان + أزرار) ثم (شريحتا المهام/الذاكرة
     داخل `Wrap` لتفادي التداخل على الشاشات الضيقة).
5. **document_screen.dart** — رفع PDF/TXT وقراءته وفهرسته **محلياً فقط**.
6. **settings_screen.dart** — المفاتيح، العدادات اليومية، ملاحظة "يعمل داخل متصفحك".
7. **memory_screen.dart** — يعرض ما يعرفه المساعد (أهداف/ذكريات/مفردات/تصحيحات/مهام/إحصاءات).

---

## 6. المفاتيح (BYOK)

- تُحفظ في **localStorage** عبر `shared_preferences`:
  - `aevora_gemini_key` (Gemini — المحادثة، المساعد، TTS الاحترافي)
  - `aevora_groq_key` (Groq — التعرف على الصوت Whisper)
  - `aevora_email` (اختياري)
- `KeySettings.hasKeys` تحدد ما إذا كان المستخدم مضى على شاشة المفاتيح.
- لا يوجد أي فحص خادم؛ تُحفظ ثم ينتقل مباشرة للتطبيق.

---

## 7. البناء والنشر

### البناء محلياً
```bash
cd aevora_web
flutter pub get
flutter run -d chrome        # تجربة سريعة
flutter analyze              # فحص (متوقع: No issues found!)
flutter test                 # الاختبارات (متوقعة: All tests passed!)
flutter build web --base-href=/aevora-backend/
```
> `--base-href=/aevora-backend/` ضروري لأن الموقع يُستضاف تحت مسار فرعي.

### النشر (GitHub Pages — فرع gh-pages)
1. **الالتزام على main** (ببيان يصف التغيير).
2. **بناء الويب** ثم:
```bash
git worktree add ../aevora-gh-pages gh-pages
rm -rf ../aevora-gh-pages/*
cp -R aevora_web/build/web/* ../aevora-gh-pages/
cd ../aevora-gh-pages
git add -A && git commit -m "Deploy: ..." && git push origin gh-pages
cd ../  && git worktree remove ../aevora-gh-pages && git worktree prune
```
3. **رفع main**: `git push origin main`.
4. الموقع الحي: **https://abowaaleed.github.io/aevora-backend/**
   (بعد أي تحديث اطلب من المستخدم `Ctrl+Shift+R` لمسح الكاش).

### PWA
- `web/manifest.json` (id/scope/اسم) — قابل للتثبيت كتطبيق على الجوال/الحاسوب.

---

## 8. التبعيات (aevora_web/pubspec.yaml)

| الحزمة | الغرض |
|---|---|
| `web: ^1.1.0` | واجهات المتصفح (DOM، Blob، HTMLAudioElement…) |
| `idb_shim: ^2.8.1` | IndexedDB (التخزين المحلي الدائم) |
| `syncfusion_flutter_pdf: ^28.1.0` | استخراج نص PDF على الويب |
| `http: ^1.2.0` | مكالمات REST المباشرة (Gemini/Groq) |
| `shared_preferences: ^2.3.2` | حفظ المفاتيح في localStorage |
| `record: ^7.1.1` | تسجيل الصوت من الميكروفون (WAV) |
| `file_picker: ^8.1.7` | اختيار الملفات (PDF/TXT) |
| `audioplayers: ^6.8.1` | تشغيل صوتي إضافي (إن استُخدم) |

**بيئة التطوير**: `sdk: ^3.12.2` · لints: `flutter_lints: ^6.0.0`.

---

## 9. ملاحظات وأخطاء سبق حلها (مهمة لتجنب العودة إليها)

- `EventListener` في `package:web` = `JSFunction`؛ استخدم `.toJS` من `dart:js_interop`.
- `idbFactory` غير مُعرّف → استخدم `idbFactoryBrowser` من `idb_browser.dart`.
- Web Speech API يُعرَّف بـ `extension type … implements JSObject`، لا `@JS() class`.
- `JSArray.from`/`add` تظهر في Dart ≥ 3.6/3.10 → لبناء مصفوفة بلوب استخدم
  `[bytes.toJS].toJS as JSArray<JSAny>` (الأنواع تُمسح وقت التشغيل).
- صوت Gemini TTS يرجع **PCM خام** `audio/L16` — يجب تغليفه في WAV قبل التشغيل.
- النموذج `gemini-2.5-flash` لم يعد متاحاً للمستخدمين الجدد → `gemini-3.6-flash`.
- ترويسة المساعد القديمة كانت صفاً واحداً → فيضان على الشاشات الضيقة؛ الحل فصل
  الشرائح في `Wrap` بسطر ثانٍ مع `TextOverflow.ellipsis`.
- البيانات **مرتبطة بالمتصفح** (IndexedDB) — رفع المستندات القديمة من السحابة لا
  ينتقل محلياً؛ اطلب من المستخدم إعادة رفع ملفاته مرة واحدة.

---

## 10. أفكار مستقبلية (غير منفذة بعد)

- تصدير/استيراد نسخة احتياطية كاملة (JSON) للترحيل بين أجهزة المتصفح.
- إضافة أصوات احترافية قابلة للاختيار (قائمة أصوات Gemini TTS).
- استخدام تدفق TTS (`streamGenerateContent`) لردود أسرع.
- عمل PWA Offline كامل عبر Service Worker (`flutter build web` + إعداد SW).
- ترجمة أسئلة المساعد إلى أكثر من لغة / إضافة وضع تدريب يومي.
- قيود العدادات قابلة للتخصيص من الإعدادات بدلاً من الثوابت.

# ايفورا — دليل المعمارية الحديثة (Zero-Cost Architecture)

> هذا المستند يصف **المعمارية الكاملة** للتطبيق كما هي الآن، ويعمل أيضاً
> كبروميت جاهز تنسخه لأي أداة ذكاء اصطناعي لفهم المشروع والاستمرار في تطويره.

---

## 1. الفكرة الجوهرية

**ايفورا** تطبيق تعليمي ذكي لتعلم الإنجليزية، أُعيدت هندسته بالكامل ليعمل
**دون أي خادم خلفي** — واجهة Flutter ويب تُنشر كـ **Static/PWA** مجانية، وكل
الذكاء يحدث **داخل متصفح المستخدم**:

- لا خادم، لا قاعدة بيانات سحابية إلزامية، لا اشتراكات.
- المستخدم يُدخل **مفاتيحه الخاصة** (BYOK: Bring Your Own Key) من Google Gemini و Groq.
- كل البيانات (محادثات، ملفات، ذاكرة المساعد، عدادات) محفوظة في **IndexedDB** بجهازه.
- **اختيارياً**: تسجيل الدخول بحساب Google يزامن البيانات بين الأجهزة عبر
  **Cloud Firestore** بمفتاح الحساب (بدون أي خادم خاص) — وبدونه يعمل كل شيء محلياً.
- التكلفة صفر تقريباً: الاستضافة مجانية (GitHub Pages)، والنماذج مجانية/رخيصة بمفاتيح المستخدم.

---

## 2. المبادئ التصميمية

| المبدأ | التنفيذ |
|---|---|
| لا خادم إطلاقاً | كل المكالمات تذهب من المتصفح مباشرة إلى مزودي النماذج (Gemini / Groq) |
| الخصوصية أولاً | المفاتيح والبيانات لا تغادر جهاز المستخدم أبداً (تُرسل المفاتيح لمزودها فقط) |
| البقاء بعد الإغلاق | تخزين IndexedDB محلي (لا يُمسح عند إغلاق المتصفح) |
| Local-first | كل شيء يعمل محلياً أولاً؛ الحساب يرفع نسخة للسحابة ولا يحجب أي وظيفة عند غيابه |
| الحساب اختياري | تسجيل الدخول بـ Google يربط البيانات بحساب المستخدم عبر Firestore (بدون خادم خاص) |
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
│   │   ├── main.dart            ← نقطة الدخول + التوجيه (أولاً الدخول ثم /shell)
│   │   ├── config.dart          ← KeySettings + AppStorage (localStorage)
│   │   ├── firebase_config.dart ← إعداد Firebase (قيم نموذجية = وضع محلي 100%)
│   │   ├── client/              ← طبقة العميل (بدون Flutter UI)
│   │   │   ├── client_storage.dart    ← قاعدة IndexedDB
│   │   │   ├── client_llm.dart        ← Gemini مباشرة (محادثة/تحليل)
│   │   │   ├── client_rag.dart        ← استخراج النصوص + بحث محلي
│   │   │   ├── client_voice.dart      ← TTS احترافي + STT (Whisper)
│   │   │   ├── client_companion.dart  ← ذاكرة المساعد ومهامه
│   │   │   ├── client_usage.dart      ← عدادات يومية محلية (usage_history)
│   │   │   ├── client_auth.dart       ← تسجيل دخول Google + الجلسة
│   │   │   ├── client_sync.dart       ← مزامنة Firestore (سحب/رفع)
│   │   │   └── client_export.dart     ← تصدير المحادثة مع ترويج
│   │   ├── screens/             ← شاشات التطبيق
│   │   │   ├── login_screen.dart      ← تسجيل الدخول بحساب Google
│   │   │   ├── shell.dart             ← الإطار + شريط التبويبات السفلي
│   │   │   ├── chat_screen.dart       ← الدردشة (Gemini + مستندات)
│   │   │   ├── companion_screen.dart  ← المساعد الشخصي
│   │   │   ├── document_screen.dart   ← رفع وفهرسة المستندات محلياً
│   │   │   ├── memory_screen.dart     ← ذاكرة المساعد والملف الشخصي
│   │   │   ├── settings_screen.dart   ← المفاتيح + العدادات + الحساب
│   │   │   └── key_setup_screen.dart  ← إدخال المفاتيح عند أول تشغيل
│   │   └── widgets/
│   │       ├── export_sheet.dart             ← نافذة تصدير المحادثة
│   │       ├── google_g_button.dart          ← زر G الرسمي (ألوان Google)
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
  stt_groq, companion}` محفوظة بمفتاح **`usage_history`** = خريطة `{date: {gemini,
  groq, whisper, companion}}` فلا تتصفّر عدادات الأيام السابقة.
- `recordGemini/recordGroq/recordWhisper/recordCompanion` — تزيد عدّاد اليوم وتُنبّه
  `SyncStore.schedulePush()` لرفع النسخة للحساب.
- `mergeHistory(cloud)` — عند السحب من السحابة يدمج يوماً بيوم (الأعلى لكل حقل يربح)
  حتى لا تُفقد العدادات عند استخدام أكثر من جهاز في نفس اليوم.
- حدود داخلية: `geminiLimit=1500` · `groqLimit=1000` · `whisperLimit=2000`
  (قيم افتراضية تقديرية قابلة للتعديل).

### 4.7 المصادقة — `client_auth.dart` + `firebase_config.dart`
- `firebase_config.dart` — ثوابت المشروع (apiKey/authDomain/projectId/…). القيم
  النموذجية `YOUR_…` تعني `isFirebaseConfigured=false` = **وضع محلي 100%** بلا Firebase؛
  بمجرد وضع القيم الحقيقية يُفعَّل Auth والمزامنة تلقائياً دون أي تعديل آخر.
- `initFirebase()` — `Firebase.initializeApp` + `setPersistence(Persistence.LOCAL)`
  لتبقى الجلسة محفوظة في المتصفح.
- `signInWithGoogle()` — `signInWithPopup(GoogleAuthProvider)` (يعمل من المتصفح مباشرة).
- `authStateStream()` — تيار حالة الجلسة؛ `currentUserId/currentEmail/currentDisplayName`.
- `signOut()` — إنهاء الجلسة (تبقى البيانات المحلية كما هي).

### 4.8 المزامنة عبر الحساب — `client_sync.dart` (`SyncStore`)
- النمط **Local-first**: IndexedDB هو المصدر الأساسي؛ Firestore مجرد نسخة مصاحبة.
- رفع (push): أي تعديل محلي (محادثة/مساعد/عدادات) يستدعي `SyncStore.schedulePush()`
  — debounce 2 ثانية ثم `set(…, merge:true)` على مستند
  `users/{uid}` (المفاتيح لا تُرفع إطلاقاً).
- سحب (pull): عند الدخول يُسحب المستند ويُطبَّق على المحلي
  (`chat_messages` مباشرة، المساعد عبر `LocalCompanion.importState`، والعدادات عبر
  `LocalUsage.mergeHistory`). `waitForReady()` (مهلة 15 ث) يمنع فتح الواجهة ببيانات
  فارغة ثم قفزها.
- كل الرفع/السحب داخل `try/catch` — أي فشل (غيار اتصال/قواعد) لا يعطّل التطبيق.
- `startListening()` يربط تغيّرات الجلسة؛ `prepare()` يسحب الجلسة الموجودة عند
  الإقلاع؛ `pushNow()` يُستخدم قبل تسجيل الخروج لتفريغ أي تعديل معلّق.

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

1. **main.dart** → `AppStorage.load()` ثم `initFirebase()`؛ إن كان Firebase مفعّلاً:
   `SyncStore.prepare()` + `startListening()` + `waitForReady()` (سحب بيانات الحساب
   قبل الواجهة). **الوجهة الأولى**: `/login` إن لم تكن هناك جلسة، وإلا `/shell`
   (وعند غياب Firebase: `/setup` أو `/shell` حسب المفاتيح).
2. **login_screen.dart** — زر "المتابعة بحساب Google" (نافذة منبثقة) + خيار
   "المتابعة بدون حساب" للمتصفحات غير المفعّلة. أي تغيّر جلسة في `authStateStream`
   يوجّه تلقائياً (دخول → `/shell`، خروج → `/login`).
3. **shell.dart** → إطار به 4 تبويبات: الدردشة · المساعد · المستندات · الإعدادات
   (مع روابط للذاكرة من الإعدادات).
4. **chat_screen.dart** — محادثة متدفقة مع Gemini + سياق RAG من المستندات +
   صوت (تسجيل/تفريغ/نطق/نطق بطيء) + لصق Word + زر **تصدير** أعلى الشاشة.
   - حقل الإدخال **متعدد الأسطر** (`multiline`، `minLines:1 maxLines:5`،
     `TextInputAction.newline`) — لا يخفي النص الطويل.
   - الرسائل تُحفظ تلقائياً بمفتاح `chat_messages` وتُنبّه المزامنة بعد الحفظ.
5. **companion_screen.dart** — مساعد يتذكر، مهام، ذكريات، مبادرة يومية.
   - الترويسة مكوّنة من سطرين: (صورة + عنوان + أزرار) ثم (شريحتا المهام/الذاكرة
     داخل `Wrap` لتفادي التداخل على الشاشات الضيقة).
6. **document_screen.dart** — رفع PDF/TXT وقراءته وفهرسته **محلياً فقط**.
7. **settings_screen.dart** — المفاتيح، العدادات اليومية، قسم "الحساب والمزامنة"
   (بريد الحساب + تسجيل الخروج من الحساب)، وزر مسح المفاتيح من المتصفح.
8. **memory_screen.dart** — يعرض ما يعرفه المساعد (أهداف/ذكريات/مفردات/تصحيحات/مهام/إحصاءات).

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
| `firebase_core: ^4.13.0` | تهيئة Firebase (تُفعل فقط عند ملء الثوابت) |
| `firebase_auth: ^6.5.7` | تسجيل الدخول بحساب Google (جلسة محفوظة) |
| `cloud_firestore: ^6.8.0` | مزامنة بيانات الحساب بين الأجهزة |
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
- **الحساب والمزامنة (المعمارية الجديدة)**: دون ملء قيم `firebase_config.dart` يعمل
  التطبيق محلياً تماماً كما كان؛ وضع القيم يفعّل شاشة الدخول والمزامنة تلقائياً.
- عند الدمج مع الحساب لا تُستخدم `JSArray.from/add` — لبناء مصفوفة بلوب استخدم
  `[bytes.toJS].toJS as JSArray<JSAny>` (انظر الملاحظة أعلاه).
- `importState` (المساعد) لا تستدعي `schedulePush` عمداً حتى لا تُحدث السحب حلقة رفع.
- المفاتيح (BYOK) **لا تُرفع للحساب أبداً** — تبقى في localStorage المحلي وحده.

---

## 10. أفكار مستقبلية (غير منفذة بعد)

- إضافة أصوات احترافية قابلة للاختيار (قائمة أصوات Gemini TTS).
- استخدام تدفق TTS (`streamGenerateContent`) لردود أسرع.
- عمل PWA Offline كامل عبر Service Worker (`flutter build web` + إعداد SW).
- ترجمة أسئلة المساعد إلى أكثر من لغة / إضافة وضع تدريب يومي.
- قيود العدادات قابلة للتخصيص من الإعدادات بدلاً من الثوابت.
- مزامنة المستندات والفهارس (chunks) مع الحساب — حالياً المستندات تبقى محلية فقط.
- دمج `usage_history` و`chat_messages` بآلية دمج أذكى عند التعديلات المتوازية.

---

## 11. تفعيل الحساب والمزامنة (Firebase Console) — مرة واحدة

بما أن المشروع **بلا خادم**، نستخدم فقط منتجات Firebase الجاهزة (Auth + Firestore)
لاستضافة هوية المستخدم ونسخته من بياناته — التكلفة صفر في الاستخدام المجاني.

1. **إنشاء المشروع**: console.firebase.google.com → إنشاء مشروع (أي اسم، بدون Google Analytics).
2. **إضافة تطبيق ويب**: أيقونة `</>` → سجّل تطبيق ويب باسم ايفورا →
   انسخ **كائن التهيئة** (apiKey، authDomain، projectId، storageBucket،
   messagingSenderId، appId) وضعه في `lib/firebase_config.dart` مكان `YOUR_…`.
3. **تفعيل Google**: Build → Authentication → Sign-in method → تمكين **Google**.
4. **النطاقات المسموحة**: في صفحة Google sign-in → Add domain:
   `abowaaleed.github.io` (لا نضع `localhost` في الإنتاج؛ للتجربة المحلية ضع `localhost`).
5. **قواعد Firestore** (Build → Firestore Database → Rules) — تقييد كل مستخدم
   ببياناته فقط:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```
6. **النشر**: بعد ذلك فقط سيرى المستخدمون شاشة الدخول، وستُرفع بياناتهم تلقائياً.

> ملاحظة: تحذير "Auth domain not configured" يظهر في لوحة التحكم فقط إذا لم يُضف
> النطاق في خطوة (4). بدون ملء الثوابت (خطوة 2) يبقى التطبيق محلياً بالكامل بلا
> أي تغيير في سلوكه.

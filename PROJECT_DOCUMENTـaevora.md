# iEvora (ايفورا) — Comprehensive Project Document

## 1. Project Overview

**iEvora** is an AI-powered English learning app with a zero-cost, client-side architecture. It supports both **Web** (Flutter web PWA) and **Android** (Flutter mobile app), sharing the same core codebase in `aevora_web/`.

### Core Principles
- **Zero-cost**: All AI processing happens client-side using user's own API keys (BYOK)
- **Privacy-first**: Data stays on device (IndexedDB); optional cloud sync via Firebase
- **No backend server** required for the current architecture
- **Free TTS**: Uses browser's Web Speech API (web) and Azure Edge TTS (Android/mobile) — no paid TTS service

### Key Features
- Chat with AI (Google Gemini)
- Voice input (Groq Whisper STT)
- Voice output (Edge TTS / Web Speech / Gemini TTS)
- Document management (PDF/TXT upload, local RAG indexing)
- AI Companion with memory, tasks, proactive suggestions
- Daily usage counters
- Firebase Auth + Firestore sync (optional)
- Export conversations (share/download/copy)

---

## 2. Project Structure

```
EnglishCompanion/
├── aevora_web/                  ← ACTIVE Flutter app (both web & Android)
│   ├── lib/
│   │   ├── main.dart            ← Entry point + routing
│   │   ├── config.dart          ← KeySettings + AppStorage (localStorage)
│   │   ├── firebase_config.dart ← Firebase config (placeholder values = local-only mode)
│   │   ├── client/              ← Core logic (no Flutter UI)
│   │   │   ├── client_storage.dart    ← IndexedDB database
│   │   │   ├── client_llm.dart        ← Gemini API (chat/analysis)
│   │   │   ├── client_rag.dart        ← Text extraction + local search
│   │   │   ├── client_voice.dart      ← TTS (Edge/Web/Gemini) + STT (Whisper)
│   │   │   ├── client_companion.dart  ← AI companion memory + tasks
│   │   │   ├── client_usage.dart      ← Daily usage counters
│   │   │   ├── client_auth.dart       ← Google sign-in + session
│   │   │   ├── client_sync.dart       ← Firestore sync (push/pull)
│   │   │   ├── client_export.dart     ← Export conversations
│   │   │   ├── client_reminders.dart  ← Local scheduled reminders
│   │   │   └── voice_platform_*.dart  ← Platform-specific TTS implementations
│   │   ├── screens/             ← UI screens
│   │   │   ├── login_screen.dart      ← Google sign-in
│   │   │   ├── shell.dart             ← Main frame + bottom nav
│   │   │   ├── chat_screen.dart       ← AI chat (Gemini + RAG)
│   │   │   ├── companion_screen.dart  ← AI companion
│   │   │   ├── document_screen.dart   ← Document management
│   │   │   ├── memory_screen.dart     ← Companion memory view
│   │   │   ├── settings_screen.dart   ← Settings (keys, voice, reminders, etc.)
│   │   │   ├── key_setup_screen.dart  ← Initial key setup
│   │   │   └── reminders_screen.dart  ← Reminder management
│   │   └── widgets/
│   │       ├── export_sheet.dart
│   │       ├── google_g_button.dart
│   │       └── plain_text_paste_dialog.dart
│   ├── android/                 ← Android-specific configuration
│   ├── web/                     ← Web-specific files (manifest.json, index.html)
│   ├── test/                    ← Test files
│   └── pubspec.yaml             ← Dependencies
├── backend/                     ← LEGACY FastAPI backend (no longer used by app)
├── frontend/                    ← LEGACY Flutter frontend (no longer used)
├── README.md                    ← Project overview
├── Dockerfile                   ← Legacy backend Docker config
├── render.yaml                  ← Legacy Render deployment config
└── .gitignore
```

---

## 3. Cloud Platforms & Services

### Active Services

| Service | Purpose | Account/Project |
|---------|---------|-----------------|
| **Google Gemini API** | AI chat, analysis, TTS | User's own API key (BYOK) |
| **Groq API** | Speech-to-text (Whisper) | User's own API key (BYOK) |
| **Azure Edge TTS** | High-quality voice synthesis (mobile) | Free, no API key needed |
| **Firebase Auth** | Google sign-in | `aevora-1f64f` |
| **Cloud Firestore** | Data sync between devices | `aevora-1f64f` |
| **GitHub Pages** | Web app hosting | `abowaaleed.github.io` |

### Legacy Services (Not Currently Used)

| Service | Purpose | Status |
|---------|---------|--------|
| Render.com | FastAPI backend hosting | Inactive (backend deprecated) |
| Firebase Hosting | Web app hosting | Configured but not used (using GitHub Pages) |

### API Keys Required (BYOK)

| Key | Where to get | Used for |
|-----|-------------|----------|
| Google Gemini API Key | https://aistudio.google.com/apikey | Chat, analysis, TTS |
| Groq API Key | https://console.groq.com | Speech-to-text (Whisper) |

---

## 4. Links & URLs

| Item | URL |
|------|-----|
| **Live Web App** | https://abowaaleed.github.io/aevora-backend/ |
| **GitHub Repository** | https://github.com/abowaaleed/aevora-backend |
| **Firebase Console** | https://console.firebase.google.com/project/aevora-1f64f |
| **Google AI Studio** | https://aistudio.google.com/apikey |
| **Groq Console** | https://console.groq.com |

---

## 5. Deployment

### Web (GitHub Pages)

```bash
cd aevora_web
flutter build web --base-href=/aevora-backend/

# Deploy to gh-pages branch
git checkout gh-pages
git rm -rf .
cp -R build/web/* .
git add .
git commit -m "Deploy: [description]"
git push origin gh-pages
git checkout main
```

**Important**: After deployment, users need `Ctrl+Shift+R` to clear cache.

### Android (APK)

```bash
cd aevora_web
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

**Note**: Release builds require ProGuard rules for notification icons:
- `android/app/proguard-rules.pro` must contain: `-keep class com.aevora.aevora_web.R$drawable { *; }`
- Must be wired in `android/app/build.gradle.kts` via `proguardFiles()`

### Firebase Hosting (Configured but Not Used)

```bash
cd aevora_web
flutter build web --release
firebase deploy --only hosting
```

**Blocker**: Firebase CLI logged in as `salehclaude411@gmail.com` but project belongs to `evora.chat@gmail.com`.

---

## 6. Local Development

### Prerequisites
- Flutter 3.44.4 / Dart 3.12.2
- Chrome (for web testing)
- Android SDK (for Android builds)

### Run Web

```bash
cd aevora_web
flutter pub get
flutter run -d chrome
```

### Run Tests

```bash
cd aevora_web
flutter test
flutter analyze
```

### Build

```bash
# Web
flutter build web --base-href=/aevora-backend/

# Android
flutter build apk --release
```

---

## 7. Key Configuration Files

### `lib/firebase_config.dart`
- Contains Firebase project configuration
- Placeholder values (`YOUR_...`) = **local-only mode** (no Firebase)
- Real values = Firebase Auth + Firestore sync enabled

### `android/app/build.gradle.kts`
- `applicationId`: `com.aevora.aevora_web`
- `minSdk`: Flutter default
- `compileSdk`: Flutter default
- ProGuard rules: `proguard-rules.pro`

### `android/app/src/main/AndroidManifest.xml`
- Permissions: INTERNET, RECORD_AUDIO, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, VIBRATE
- App label: `ايفورا`
- Notification receivers for scheduled reminders

### `pubspec.yaml`
- Version: `1.5.0+15`
- SDK: `^3.12.2`

---

## 8. Dependencies

### Core Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_edge_tts` | `^0.0.2` | Edge TTS (Azure neural voices, free) |
| `flutter_tts` | `^4.2.5` | Platform TTS fallback |
| `audioplayers` | `^6.8.1` | Audio playback |
| `record` | `^7.1.1` | Microphone recording (WAV) |
| `shared_preferences` | `^2.3.2` | localStorage (keys, settings) |
| `idb_shim` | `^2.8.1` | IndexedDB (local database) |
| `syncfusion_flutter_pdf` | `^28.1.0` | PDF text extraction |
| `firebase_core` | `^4.13.0` | Firebase initialization |
| `firebase_auth` | `^6.5.7` | Google sign-in |
| `cloud_firestore` | `^6.8.0` | Data sync |
| `http` | `^1.2.0` | API calls (Gemini, Groq) |
| `web` | `^1.1.0` | Browser APIs (DOM, Blob, Audio) |
| `file_picker` | `^12.0.0` | File selection |
| `flutter_local_notifications` | `^19.4.0` | Local notifications (Android) |
| `timezone` | `^0.10.1` | Timezone handling |
| `flutter_timezone` | `^4.1.0` | Device timezone |
| `crypto` | `^3.0.7` | Cryptographic functions |
| `google_sign_in` | `^7.2.0` | Google authentication |
| `url_launcher` | `^6.3.2` | Opening URLs |
| `archive` | `^4.0.9` | Archive handling |
| `xml` | `^6.6.1` | XML parsing |

### Dev Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_test` | SDK | Testing framework |
| `flutter_launcher_icons` | `^0.14.3` | App icon generation |
| `flutter_lints` | `^6.0.0` | Code linting |

---

## 9. Architecture Details

### Platform-Specific TTS

**Web** (`voice_platform_web.dart`):
- `speakEdgeTts()`: Splits text by language (Arabic/English), sends to Azure Edge TTS via WebSocket, plays via HTML5 Audio element
- `previewEdgeVoice()`: Uses HTML5 Audio for preview
- `loadEdgeVoices()`: Returns static list of available voices
- Uses `stripForTts()` to clean markdown before synthesis

**Mobile** (`voice_platform_stub.dart`):
- `speakEdgeTts()`: Uses `flutter_edge_tts` package directly
- `previewEdgeVoice()`: Uses FlutterEdgeTts + audioplayers
- `loadEdgeVoices()`: Queries available Edge TTS voices

**Shared** (`client_voice.dart`):
- `stripForTts()`: Removes markdown formatting (`**`, `#`, `` ` ``, `- `, etc.)
- `ttsSegments()`: Splits text into Arabic/English segments for dual-voice synthesis
- `speakSmart()`: Tries Gemini TTS → Edge TTS → Web Speech API fallback chain

### Data Storage

**IndexedDB** (browser/device):
- `kv` store: Key-value pairs (settings, keys)
- `files` store: File metadata
- `blobs` store: File contents
- `chunks` store: RAG index chunks
- `usage_history`: Daily API usage counters
- `chat_messages`: Conversation history
- `companion_*`: AI companion state (profile, memories, tasks)

**Firebase Firestore** (optional sync):
- `users/{uid}`: User data (excluding API keys)
- Sync triggered on local changes (2s debounce)
- Pull on app startup

### AI Integration

**Gemini API**:
- Chat: `gemini-3.6-flash` via streaming SSE
- Analysis: `geminiChatSync` for background processing
- TTS: `gemini-3.1-flash-tts-preview` (optional, premium)

**Groq API**:
- STT: `whisper-large-v3` via REST API

**Edge TTS**:
- Free Azure neural voices
- Default Arabic: `ar-SA-HamedNeural`
- Default English: `en-US-JennyNeural`
- Dual-voice: Text split by language, each segment synthesized with appropriate voice

---

## 10. Important Notes & Gotchas

### Development
- **Always run `flutter analyze` and `flutter test` before committing**
- **Web build requires `--base-href=/aevora-backend/`** for GitHub Pages
- **Android release builds need ProGuard rules** for notification icons
- **Edge TTS on web uses HTML5 Audio** (not Web Audio API) to avoid autoplay policy issues
- **Edge TTS text must be stripped of markdown** before synthesis (use `stripForTts()`)

### Firebase
- **Firebase CLI account mismatch**: Logged in as `salehclaude411@gmail.com` but project belongs to `evora.chat@gmail.com`. Need to run `firebase login` manually to re-authenticate.
- **Firebase Hosting not used**: Deploying via GitHub Pages instead.

### Deployment
- **GitHub Pages**: After deploy, users need `Ctrl+Shift+R` to clear cache
- **Android APK**: No Play Store signing configured (using debug keys)
- **No iOS**: iOS not configured (only web and Android)

### Known Issues
- **Notification icon on Android**: Requires ProGuard keep rule (already fixed)
- **Edge TTS on web**: Must use HTML5 Audio, not Web Audio API (autoplay policy)
- **Gemini TTS**: Returns raw PCM audio, needs WAV wrapping before playback

---

## 11. Future Plans (Not Yet Implemented)

- [ ] Add voice selection UI with preview for Edge TTS
- [ ] Implement offline PWA with Service Worker
- [ ] Add multi-language support for companion questions
- [ ] Make usage counter limits customizable in settings
- [ ] Sync documents/indexes with Firebase (currently local only)
- [ ] Implement smarter merge for concurrent edits
- [ ] Add Gemini TTS as premium voice option
- [ ] Implement streaming TTS for faster responses

---

## 12. Testing

### Run All Tests

```bash
cd aevora_web
flutter test
```

**Current status**: 75/75 tests pass

### Key Test Files

- `test/client_rag_test.dart`: RAG indexing and retrieval
- `test/client_companion_test.dart`: Companion memory and tasks
- `test/client_usage_test.dart`: Usage counter logic
- `test/client_export_test.dart`: Export functionality

---

## 13. Environment Variables & Secrets

**No environment variables required** — all configuration is in code or user-provided keys.

### User-Provided Keys (stored in localStorage)

| Key Name | Purpose |
|----------|---------|
| `aevora_gemini_key` | Google Gemini API key |
| `aevora_groq_key` | Groq API key |
| `aevora_email` | Optional email |

### Firebase Configuration

In `lib/firebase_config.dart`:
- `apiKey`: Firebase web API key
- `authDomain`: `aevora-1f64f.firebaseapp.com`
- `projectId`: `aevora-1f64f`
- `storageBucket`: `aevora-1f64f.appspot.com`
- `messagingSenderId`: `803434626582`
- `appId`: `1:803434626582:web:150f8c0f0b2b5b5b5b5b5b`

---

## 14. Git Workflow

- **Main branch**: `main` (development)
- **Deployment branch**: `gh-pages` (GitHub Pages)
- **Commit style**: Conventional commits (e.g., `fix:`, `feat:`, `refactor:`)
- **No auto-commit**: Only commit when explicitly requested

### Recent Changes

1. Added dual-voice Edge TTS (Arabic/English)
2. Added markdown stripping for TTS
3. Added voice selection in settings
4. Added document and reminder sections in settings
5. Fixed Android notification icon with ProGuard
6. Fixed robotic voice on web (HTML5 Audio instead of Web Audio API)
7. Deployed to GitHub Pages

---

## 15. Quick Reference

### Essential Commands

```bash
# Run web
cd aevora_web && flutter run -d chrome

# Build web
cd aevora_web && flutter build web --base-href=/aevora-backend/

# Build Android
cd aevora_web && flutter build apk --release

# Run tests
cd aevora_web && flutter test

# Analyze code
cd aevora_web && flutter analyze

# Deploy web
git checkout gh-pages && git rm -rf . && cp -R aevora_web/build/web/* . && git add . && git commit -m "Deploy" && git push origin gh-pages && git checkout main
```

### Key Files to Check

- `lib/client/client_voice.dart`: Voice logic
- `lib/client/voice_platform_web.dart`: Web TTS
- `lib/client/voice_platform_stub.dart`: Mobile TTS
- `lib/screens/settings_screen.dart`: Settings UI
- `android/app/proguard-rules.pro`: Android build rules
- `lib/firebase_config.dart`: Firebase configuration

---

*Last updated: 2026-08-18*
*Version: 1.5.0+15*
*Status: Active development (Web + Android)*

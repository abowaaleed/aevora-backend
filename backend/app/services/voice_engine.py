import os
import subprocess
import tempfile
import wave
import math
import struct
import re
import asyncio
from typing import Optional


class VoiceEngine:
    """
    Voice Engine for Aevora companion.
    Handles Speech-to-Text (STT) and Text-to-Speech (TTS).
    """
    _model = None

    @classmethod
    def get_model(cls):
        if cls._model is None:
            from faster_whisper import WhisperModel
            # Load base model for better Arabic accuracy while maintaining reasonable speed
            cls._model = WhisperModel("base", device="cpu", compute_type="int8")
        return cls._model

    def transcribe(self, audio_bytes: bytes, language: Optional[str] = None) -> str:
        """
        Transcribe audio bytes into text (Speech-to-Text).
        Uses Gemini when available/fast (cloud), falls back to local faster-whisper.
        `language` (ar/en/...) اختياري — عند تركه يُكتشف تلقائياً من الصوت.
        """
        import time
        start_t = time.time()
        if not audio_bytes:
            print("[VOICE ENGINE] Empty audio bytes received")
            return ""

        # Prefer Gemini on Render (cloud, fast); use Groq Whisper as the fallback
        # when Gemini is unavailable/quota-exhausted; local faster-whisper last.
        engine = os.getenv("STT_ENGINE", "gemini" if os.getenv("RENDER") else "whisper")
        # Groq Whisper (whisper-large-v3-turbo) هو الأسرع — جرّبه أولاً متى توفر
        # مفتاح Groq (مفتاح مستخدم أو مفتاح خادم)، ثم Gemini، وأخيراً whisper المحلي.
        from app.core.user_context import current_groq_key, current_gemini_key
        if current_groq_key() or os.getenv("GROQ_API_KEY"):
            text = self._transcribe_groq(audio_bytes, language=language)
            if text:
                print(f"[VOICE ENGINE] Total transcribe method time: {time.time() - start_t:.3f}s (Groq Whisper)")
                return text
            print("[VOICE ENGINE] Groq Whisper empty/failed, trying Gemini")

        # Gemini للصوت يُستعمل فقط عند ضبط STT_ENGINE=gemini وتوفر مفتاح
        # (في الوضع العام لا يُستعمل بدون مفتاح المستخدم).
        gemini_key_available = bool(current_gemini_key() or os.getenv("GEMINI_API_KEY"))
        if engine == "gemini" and gemini_key_available:
            text = self._transcribe_gemini(audio_bytes, language=language)
            if text:
                print(f"[VOICE ENGINE] Total transcribe method time: {time.time() - start_t:.3f}s (Gemini)")
                return text
            print("[VOICE ENGINE] Gemini transcription empty/failed, trying faster-whisper")

        # Write input bytes to a temporary file
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_wav:
            temp_wav.write(audio_bytes)
            temp_path = temp_wav.name

        print(f"[VOICE ENGINE] Saved input to {temp_path} ({len(audio_bytes)} bytes)")

        try:
            converted_path = temp_path
            # Try to convert and normalize audio format (16kHz mono) using pydub if possible
            try:
                from pydub import AudioSegment
                sound = AudioSegment.from_file(temp_path)
                sound = sound.set_frame_rate(16000).set_channels(1)
                
                converted_path = temp_path + "_converted.wav"
                sound.export(converted_path, format="wav")
                print(f"[VOICE ENGINE] Normalized audio saved to {converted_path}")
            except Exception as pe:
                print(f"[VOICE ENGINE] pydub normalization failed/unavailable: {pe}. Passing raw WAV directly to Whisper.")
            
            # Run local faster-whisper model
            print("[VOICE ENGINE] Starting Faster-Whisper inference...")
            whisper_start = time.time()
            model = self.get_model()
            segments, info = model.transcribe(converted_path, beam_size=5)
            text = " ".join([segment.text for segment in segments])
            whisper_end = time.time()
            print(f"[VOICE ENGINE] Inference complete in {whisper_end - whisper_start:.3f}s. Result: '{text}'")

            if converted_path != temp_path and os.path.exists(converted_path):
                os.remove(converted_path)
                
            return text.strip()
        except Exception as e:
            print("[VOICE ENGINE] Faster-Whisper Transcription error:", e)
            return ""
        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)
            print(f"[VOICE ENGINE] Total transcribe method time: {time.time() - start_t:.3f}s")

    def _transcribe_gemini(self, audio_bytes: bytes, language: Optional[str] = None) -> str:
        """Transcribe audio using the Gemini API (fast, cloud-based)."""
        import time
        start_t = time.time()
        from app.services.gemini_service import GeminiService
        from app.usage.service import record_provider_usage
        from app.core.user_context import current_user_id
        service = GeminiService()
        mime = "audio/wav" if audio_bytes.startswith(b"RIFF") else "audio/mpeg"
        try:
            text = service.transcribe_audio(audio_bytes, mime, language=language)
            record_provider_usage("stt_gemini", current_user_id())
            print(f"[VOICE ENGINE] Gemini transcription complete in {time.time() - start_t:.3f}s: '{text[:120]}'")
            return text
        except Exception as e:
            print(f"[VOICE ENGINE] Gemini transcription failed: {e}")
            return ""

    def _transcribe_groq(self, audio_bytes: bytes, language: Optional[str] = None) -> str:
        """Transcribe audio using Groq's hosted Whisper (cloud fallback)."""
        try:
            from app.providers.groq_provider import GroqProvider
            from app.usage.service import record_provider_usage
            from app.core.user_context import current_user_id
            provider = GroqProvider()
            if not provider.available:
                print("[VOICE ENGINE] Groq API key not set — skipping Groq Whisper")
                return ""
            payload = audio_bytes
            filename = "evora_audio.wav"
            # Groq Whisper expects common audio formats (mp3/wav/m4a/ogg/flac).
            # Normalize anything else (e.g. AIFF from the 'say' fallback) to WAV.
            try:
                from pydub import AudioSegment
                import io as _io
                sound = AudioSegment.from_file(_io.BytesIO(audio_bytes))
                wav_buf = _io.BytesIO()
                sound.set_frame_rate(16000).set_channels(1).export(wav_buf, format="wav")
                payload = wav_buf.getvalue()
            except Exception as ne:
                print(f"[VOICE ENGINE] pydub normalization skipped for Groq: {ne}")
            text = provider.transcribe_audio(payload, filename=filename, language=language)
            record_provider_usage("stt_groq", current_user_id())
            return text
        except Exception as e:
            print(f"[VOICE ENGINE] Groq Whisper transcription failed: {e}")
            return ""

    def _clean_text_for_tts(self, text: str) -> str:
        """
        Removes Markdown, URLs, and code blocks to ensure natural reading.
        """
        # Remove code blocks
        text = re.sub(r'```.*?```', '', text, flags=re.DOTALL)
        # Remove inline code
        text = re.sub(r'`.*?`', '', text)
        # Remove Markdown symbols (*, _, #)
        text = re.sub(r'[\*_#]', '', text)
        # Remove URLs
        text = re.sub(r'http[s]?://\S+', '', text)
        # Remove common technical symbols that shouldn't be read
        text = re.sub(r'[\[\]\(\)\{\}\-\+]', ' ', text)
        # Ensure single spaces
        text = re.sub(r'\s+', ' ', text)
        return text.strip()

    def _apply_natural_pauses(self, text: str, pause_ms: int = 400) -> str:
        """
        Adds subtle logic to the text to help edge-tts prosody.
        """
        # Ensure spaces after punctuation for natural breath
        text = text.replace(".", ". ")
        text = text.replace("،", "، ")
        text = text.replace(",", ", ")
        text = text.replace("؟", "؟ ")
        text = text.replace("?", "? ")
        return text

    def _is_female(self, voice_id: str) -> bool:
        """Determines if a voice ID corresponds to a female voice."""
        if not voice_id: return False
        female_names = ['aria', 'sonia', 'zariyah', 'natasha', 'jenny', 'libby', 'samantha', 'victoria']
        return any(name in voice_id.lower() for name in female_names)

    @staticmethod
    def _wrap_linear16_wav(pcm: bytes, rate: int) -> bytes:
        """يلف عينات PCM (L16) في غلاف WAV ليعمل عبر المتصفح."""
        import wave
        import io
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(pcm)
        return buf.getvalue()

    def _synthesize_gemini(self, text: str, voice: Optional[str] = None) -> Optional[bytes]:
        """TTS من Gemini (gemini-2.5-flash-preview-tts): صوت بشري طبيعي
        يتقن العربية والإنجليزية ويعالج خلط اللغتين في نص واحد.
        يستعمل مفتاح المستخدم في الوضع العام (أو مفتاح الخادم إن وُجد)."""
        import httpx
        import base64
        from app.core.user_context import current_gemini_key
        key = current_gemini_key() or os.getenv("GEMINI_API_KEY")
        if not key:
            return None
        try:
            url = (
                "https://generativelanguage.googleapis.com/v1beta/models/"
                f"gemini-2.5-flash-preview-tts:generateContent?key={key}"
            )
            # صوت بشري متعدد اللغات (يدعم العربية والإنجليزية معاً).
            voice_name = "sulafat"
            payload = {
                "contents": [{"parts": [{"text": text}]}],
                "generationConfig": {
                    "responseModalities": ["AUDIO"],
                    "speechConfig": {
                        "voiceConfig": {
                            "prebuiltVoiceConfig": {"voiceName": voice_name}
                        }
                    },
                },
            }
            resp = httpx.post(url, json=payload, timeout=120.0)
            if resp.status_code != 200:
                print(f"[VOICE ENGINE] Gemini TTS error {resp.status_code}: {resp.text[:200]}")
                return None
            obj = resp.json()
            parts = (obj.get("candidates") or [{}])[0].get("content", {}).get("parts") or []
            audio = None
            mime = ""
            for p in parts:
                inline = p.get("inlineData") or {}
                if inline.get("data"):
                    audio = base64.b64decode(inline["data"])
                    mime = inline.get("mimeType") or ""
                    break
            if not audio:
                print("[VOICE ENGINE] Gemini TTS returned no audio")
                return None
            print(f"[VOICE ENGINE] Gemini TTS bytes: {len(audio)} ({mime})")
            if "L16" in mime or "l16" in mime:
                rate = 24000
                m = re.search(r"rate=(\d+)", mime)
                if m:
                    rate = int(m.group(1))
                return self._wrap_linear16_wav(audio, rate)
            return audio
        except Exception as e:
            print(f"[VOICE ENGINE] Gemini TTS failed: {e}")
            return None

    def _edge_synthesize_once(self, text: str, voice: str, rate: str, pitch: str) -> bytes:
        """توليد مقطع واحد عبر edge-tts في خيط/حلقة مستقلة."""
        import edge_tts
        import concurrent.futures

        async def _inner():
            communicate = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
            with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as temp_mp3:
                temp_path = temp_mp3.name
            try:
                await communicate.save(temp_path)
                with open(temp_path, "rb") as f:
                    return f.read()
            finally:
                if os.path.exists(temp_path):
                    os.remove(temp_path)

        def _run_async():
            new_loop = asyncio.new_event_loop()
            try:
                return new_loop.run_until_complete(_inner())
            finally:
                new_loop.close()

        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            return pool.submit(_run_async).result(timeout=60)

    def _split_language_runs(self, text: str, ar_voice: str, en_voice: str):
        """تقسيم النص إلى مقاطع متصلة حسب اللغة حتى يُقرأ كل جزء بصوته الصحيح.
        (صوت عربي للعربية، وصوت إنجليزي للإنجليزية) — لحل خلط اللغتين في رد واحد."""
        tokens = re.findall(
            r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]+'
            r'|[A-Za-z0-9]+'
            r'|[^A-Za-z\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]+',
            text,
        )
        runs = []
        for tok in tokens:
            if re.search(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]', tok):
                kind = True
            elif re.search(r'[A-Za-z0-9]', tok):
                kind = False
            else:
                if runs:
                    runs[-1] = (runs[-1][0], runs[-1][1] + tok)
                else:
                    runs.append((False, tok))
                continue
            if runs and runs[-1][0] == kind:
                runs[-1] = (kind, runs[-1][1] + tok)
            else:
                runs.append((kind, tok))
        segments = []
        for is_ar, seg in runs:
            seg = seg.strip()
            if not seg:
                continue
            segments.append((ar_voice if is_ar else en_voice, seg))
        return segments

    def synthesize(self, text: str, voice: Optional[str] = None, rate: Optional[str] = None, pitch: Optional[str] = None) -> bytes:
        """
        Synthesize text into expressive human-like speech.
        يفضّل Gemini TTS (صوت بشري، يجيد العربية والإنجليزية وخلطهما)
        عند توفر مفتاح وسرعة افتراضية، وإلا edge-tts (يدعم الإبطاء/الحدة)
        مع تقسيم النص لكل لغة بصوتها.
        """
        if not text:
            return b""

        # 1. Clean Text
        clean_text = self._clean_text_for_tts(text)
        if not clean_text: return b""

        # 2. Phrasing/Pauses
        clean_text = self._apply_natural_pauses(clean_text)

        # 3. TTS engine: Gemini أولاً (صوت بشري) — إلا مع طلب إبطاء/حدة
        #    أو تعطيل TTS_ENGINE=edge صراحةً.
        engine_setting = os.getenv("TTS_ENGINE", "auto")
        default_speed = not rate or "+0%" in rate
        neutral_pitch = not pitch or pitch in ("+0%", "+0Hz")
        use_gemini = (
            engine_setting != "edge"
            and default_speed
            and neutral_pitch
        )
        if use_gemini:
            gemini_audio = self._synthesize_gemini(clean_text, voice=voice)
            if gemini_audio:
                print(f"[VOICE ENGINE] Gemini TTS synthesized. Bytes: {len(gemini_audio)}")
                return gemini_audio
            print("[VOICE ENGINE] Gemini TTS unavailable — falling back to edge-tts")

        # 4. Detect language
        arabic_chars = len(re.findall(r'[\u0600-\u06FF]', clean_text))
        english_chars = len(re.findall(r'[a-zA-Z]', clean_text))
        has_arabic = arabic_chars > 0
        is_primarily_arabic = arabic_chars >= english_chars

        # 5. Determine Target Voice
        print(f"[VOICE ENGINE] TTS REQUEST - Voice: '{voice}', Rate: '{rate}', Pitch: '{pitch}'")
        print(f"[VOICE ENGINE] TEXT ANALYSIS - Arabic chars: {arabic_chars}, English chars: {english_chars}, Has Arabic: {has_arabic}")

        is_female_requested = self._is_female(voice)

        # صوت عربي وصوت إنجليزي (للتقسيم حسب اللغة في النصوص المختلطة)
        if voice and voice.startswith("ar-"):
            ar_voice = voice
        else:
            ar_voice = "ar-SA-ZariyahNeural" if is_female_requested else "ar-SA-HamedNeural"
        if voice and voice.startswith("en-"):
            en_voice = voice
        else:
            en_voice = "en-US-AriaNeural" if is_female_requested else "en-US-AndrewNeural"

        # الصوت الأساسي (للسجل وللاحتياط النهائي) حسب اللغة الغالبة
        if voice:
            target_voice = voice
            if has_arabic and not voice.startswith("ar-"):
                target_voice = ar_voice
                print(f"[VOICE ENGINE] LANG MISMATCH: English voice '{voice}' requested for Arabic text. Overriding to '{target_voice}' (Female: {is_female_requested}).")
            elif not has_arabic and voice.startswith("ar-"):
                target_voice = en_voice
                print(f"[VOICE ENGINE] LANG MISMATCH: Arabic voice '{voice}' requested for English text. Overriding to '{target_voice}' (Female: {is_female_requested}).")
            else:
                print(f"[VOICE ENGINE] LANG MATCH: Keeping user voice selection '{target_voice}'")
        else:
            target_voice = ar_voice if is_primarily_arabic else en_voice
            print(f"[VOICE ENGINE] NO VOICE PROVIDED: Defaulting to '{target_voice}'")

        # 6. Parameters (Edge-TTS format: rate uses %, pitch uses Hz)
        # Clean up any malformed pitch strings (e.g. "+0%Hz")
        clean_pitch = pitch
        if clean_pitch and "%Hz" in clean_pitch:
            clean_pitch = clean_pitch.replace("%Hz", "Hz")

        target_rate = rate if rate and ('%' in rate) else "+0%"

        # Convert pitch from % format (from frontend) to Hz format (required by edge-tts)
        # Frontend sends e.g. "+0%", "+12%", "-10%". edge-tts requires "+0Hz", "+6Hz", "-5Hz".
        if clean_pitch and '%' in clean_pitch and 'Hz' not in clean_pitch:
            try:
                pct = int(clean_pitch.replace('%', '').replace('+', ''))
                hz = int(pct * 0.5)  # scale % to Hz (50% range -> 25Hz range)
                target_pitch = f"+{hz}Hz" if hz >= 0 else f"{hz}Hz"
            except ValueError:
                target_pitch = "+0Hz"
        elif clean_pitch and 'Hz' in clean_pitch:
            target_pitch = clean_pitch
        else:
            target_pitch = "+0Hz"

        print(f"[VOICE ENGINE] Final synthesis decision: Voice='{target_voice}', Rate='{target_rate}', Pitch='{target_pitch}'")

        try:
            # توليد صوتي: تقسيم النص المختلط لكل لغة بصوتها ثم دمج مقاطع MP3.
            segments = self._split_language_runs(clean_text, ar_voice, en_voice)
            if len(segments) <= 1:
                audio_result = self._edge_synthesize_once(
                    clean_text, target_voice, target_rate, target_pitch
                )
                print(f"[VOICE ENGINE] edge-tts synthesis successful (single). Bytes: {len(audio_result)}")
            else:
                blobs = [
                    self._edge_synthesize_once(seg_text, seg_voice, target_rate, target_pitch)
                    for seg_voice, seg_text in segments
                ]
                if any(b is None or not b for b in blobs):
                    raise RuntimeError("segment synthesis returned empty audio")
                audio_result = b"".join(blobs)
                print(f"[VOICE ENGINE] edge-tts blend successful ({len(segments)} segments, {len(audio_result)} bytes)")
            return audio_result

        except Exception as e:
            print(f"[VOICE ENGINE] CRITICAL ERROR: edge-tts pipeline failed for voice '{target_voice}': {e}")
            import traceback
            traceback.print_exc()
            print("[VOICE ENGINE] Attempting fallback to macOS 'say'...")

        # 6. Fallback to macOS 'say'
        try:
            result = subprocess.run(["which", "say"], capture_output=True, text=True)
            if result.returncode == 0:
                print(f"[VOICE ENGINE] Fallback: Using macOS 'say' for text. Primarily Arabic: {is_primarily_arabic}")
                with tempfile.NamedTemporaryFile(suffix=".aiff", delete=False) as temp_audio:
                    temp_path = temp_audio.name
                
                say_rate = 180
                if "-" in target_rate: say_rate = 140
                elif "+" in target_rate: say_rate = 220

                cmd = ["say", "-r", str(say_rate), "-o", temp_path]
                if is_primarily_arabic:
                    # 'Laila' is the standard female Arabic voice on macOS, if installed.
                    # 'Majed' is the male one. We'll try Laila if female requested.
                    say_voice = "Laila" if is_female_requested else "Majed"
                    cmd += ["-v", say_voice]
                    print(f"[VOICE ENGINE] Fallback Voice: {say_voice} (Arabic)")
                else:
                    say_voice = "Samantha" if is_female_requested else "Alex"
                    cmd += ["-v", say_voice]
                    print(f"[VOICE ENGINE] Fallback Voice: {say_voice} (English)")
                cmd.append(clean_text)
                subprocess.run(cmd, check=True)
                
                with open(temp_path, "rb") as f:
                    audio_data = f.read()
                if os.path.exists(temp_path): os.remove(temp_path)
                return audio_data
            else:
                print("[VOICE ENGINE] 'say' command not found.")
        except Exception as se:
            print(f"[VOICE ENGINE] Fallback 'say' failed: {se}")
        except: pass

        return self._generate_silent_wav()

    def _generate_silent_wav(self) -> bytes:
        """Generates a short silent clip as a last resort."""
        sample_rate = 8000
        duration = 0.5
        num_samples = int(duration * sample_rate)
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_wav:
            temp_path = temp_wav.name
        try:
            with wave.open(temp_path, "w") as wav_file:
                wav_file.setparams((1, 2, sample_rate, num_samples, "NONE", "not compressed"))
                wav_file.writeframesraw(b'\x00' * (num_samples * 2))
            with open(temp_path, "rb") as f:
                audio_bytes = f.read()
            return audio_bytes
        finally:
            if os.path.exists(temp_path): os.remove(temp_path)

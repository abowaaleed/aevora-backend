import sys
import os

# Add the project root to sys.path so 'app' can be found
# Current file is in EnglishCompanion root
sys.path.append(os.path.join(os.getcwd(), 'backend'))

from app.services.voice_engine import VoiceEngine
import time

def test_tts():
    engine = VoiceEngine()

    print("--- Testing English TTS (edge-tts) ---")
    en_text = "Hello, how are you today? I am a neural voice from Microsoft."
    start = time.time()
    en_audio = engine.synthesize(en_text)
    latency = time.time() - start
    print(f"English audio size: {len(en_audio)} bytes, Latency: {latency:.3f}s")
    with open("test_en.mp3", "wb") as f:
        f.write(en_audio)

    print("\n--- Testing Arabic TTS (macOS say) ---")
    ar_text = "مرحبا، كيف حالك اليوم؟ أنا صوت من نظام ماك."
    start = time.time()
    ar_audio = engine.synthesize(ar_text)
    latency = time.time() - start
    print(f"Arabic audio size: {len(ar_audio)} bytes, Latency: {latency:.3f}s")
    with open("test_ar.aiff", "wb") as f:
        f.write(ar_audio)

    print("\n--- Testing Mixed (Majority English) ---")
    mixed_text = "Hello my friend. How are you doing? مرحبا بك."
    en_count = sum(1 for c in mixed_text if c.isalpha()) # roughly
    ar_count = sum(1 for c in mixed_text if '\u0600' <= c <= '\u06FF')
    print(f"Counts: EN {en_count}, AR {ar_count}")
    mixed_audio = engine.synthesize(mixed_text)
    print(f"Mixed audio size: {len(mixed_audio)} bytes")

if __name__ == "__main__":
    test_tts()

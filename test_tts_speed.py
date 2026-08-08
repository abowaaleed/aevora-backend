import sys
import os
import time

# Add backend to path
sys.path.append(os.path.join(os.getcwd(), 'backend'))

from app.services.voice_engine import VoiceEngine

def test_tts_speed():
    engine = VoiceEngine()

    print("--- Testing English TTS Normal Speed ---")
    en_text = "Hello, how are you today? I am speaking at a normal pace."
    start = time.time()
    en_audio_normal = engine.synthesize(en_text)
    print(f"Normal audio size: {len(en_audio_normal)} bytes, Latency: {time.time() - start:.3f}s")
    with open("test_en_normal.mp3", "wb") as f:
        f.write(en_audio_normal)

    print("\n--- Testing English TTS Slow Speed (-25%) ---")
    start = time.time()
    en_audio_slow = engine.synthesize(en_text, rate="-25%")
    print(f"Slow audio size: {len(en_audio_slow)} bytes, Latency: {time.time() - start:.3f}s")
    with open("test_en_slow.mp3", "wb") as f:
        f.write(en_audio_slow)

    print("\n--- Testing Arabic TTS Normal Speed ---")
    ar_text = "مرحبا كيف حالك اليوم؟"
    start = time.time()
    ar_audio_normal = engine.synthesize(ar_text)
    print(f"Arabic normal audio size: {len(ar_audio_normal)} bytes, Latency: {time.time() - start:.3f}s")

    print("\n--- Testing Arabic TTS Slow Speed ---")
    start = time.time()
    ar_audio_slow = engine.synthesize(ar_text, rate="-25%")
    print(f"Arabic slow audio size: {len(ar_audio_slow)} bytes, Latency: {time.time() - start:.3f}s")

if __name__ == "__main__":
    test_tts_speed()

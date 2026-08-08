import sys
import os
import time
from pathlib import Path

# Add project root to path
sys.path.append(str(Path(__file__).parent.parent))

from app.services.voice_engine import VoiceEngine

def measure_base_stt():
    engine = VoiceEngine()
    # Path to the 7MB English sample that worked before
    audio_path = "../sample_speech.wav"
    if not os.path.exists(audio_path):
        print(f"Audio file {audio_path} not found!")
        return

    with open(audio_path, "rb") as f:
        audio_bytes = f.read()

    print(f"Measuring Whisper-base performance on {len(audio_bytes)} bytes...")

    # Pre-load model to exclude load time from transcription measurement
    engine.get_model()

    start_time = time.perf_counter()
    text = engine.transcribe(audio_bytes)
    end_time = time.perf_counter()

    duration = end_time - start_time
    print(f"Transcribed Text: '{text}'")
    print(f"STT Duration (base): {duration:.2f} seconds")

if __name__ == "__main__":
    measure_base_stt()

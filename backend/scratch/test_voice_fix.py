import sys
import os
from pathlib import Path

# Add project root to path
sys.path.append(str(Path(__file__).parent.parent))

from app.services.voice_engine import VoiceEngine

def test_transcription():
    engine = VoiceEngine()
    audio_path = "../arabic_test.wav"
    if not os.path.exists(audio_path):
        print(f"Audio file {audio_path} not found!")
        return

    with open(audio_path, "rb") as f:
        audio_bytes = f.read()

    print(f"Transcribing {len(audio_bytes)} bytes...")
    text = engine.transcribe(audio_bytes)
    print(f"Transcribed Text: '{text}'")

    if text.lower().strip() == "this is a test of the voice system":
        print("SUCCESS: Transcription matches!")
    else:
        print(f"Partial success or mismatch. Received: '{text}'")

if __name__ == "__main__":
    test_transcription()

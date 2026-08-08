import pytest
from fastapi.testclient import TestClient
from unittest.mock import MagicMock
from main import app
from app.services.voice_engine import VoiceEngine


client = TestClient(app)


@pytest.fixture(autouse=True)
def mock_whisper(monkeypatch):
    mock_model = MagicMock()
    
    def mock_transcribe_fn(audio_path, **kwargs):
        import os
        try:
            size = os.path.getsize(audio_path)
        except:
            size = 100
            
        class Segment:
            def __init__(self, text):
                self.text = text
        
        if size == 100:
            segments = [Segment("Hello Aevora")]
        elif size == 200:
            segments = [Segment("What is the weather in Rome?")]
        elif size == 150:
            segments = [Segment("This is a simulated transcription of your voice query.")]
        else:
            segments = [Segment("Simulated transcription")]
        return segments, None
        
    mock_model.transcribe.side_effect = mock_transcribe_fn
    monkeypatch.setattr(VoiceEngine, "get_model", classmethod(lambda cls: mock_model))


class TestVoiceEngine:
    """Test cases for VoiceEngine service."""

    def test_voice_engine_transcribe_success(self):
        engine = VoiceEngine()
        result = engine.transcribe(b"A" * 100)
        assert result == "Hello Aevora"

    def test_voice_engine_transcribe_empty(self):
        engine = VoiceEngine()
        result = engine.transcribe(b"")
        assert result == ""

    def test_voice_engine_synthesize_success(self):
        engine = VoiceEngine()
        audio_data = engine.synthesize("Hello Aevora")
        assert len(audio_data) > 0
        # Should be a valid wave or aiff format
        assert audio_data.startswith(b"RIFF") or audio_data.startswith(b"FORM")

    def test_voice_engine_transcribe_other_lengths(self):
        engine = VoiceEngine()
        assert engine.transcribe(b"A" * 200) == "What is the weather in Rome?"
        assert engine.transcribe(b"A" * 150) == "This is a simulated transcription of your voice query."

    def test_voice_engine_synthesize_fallback(self, monkeypatch):
        import subprocess
        # Force native macOS checks to fail/raise to enter procedural fallback
        monkeypatch.setattr(subprocess, "run", MagicMock(side_effect=Exception("mock native error")))
        
        engine = VoiceEngine()
        audio_data = engine.synthesize("Hello Fallback")
        assert len(audio_data) > 0
        assert audio_data.startswith(b"RIFF")



class TestVoiceAPI:
    """Test cases for Voice API router endpoints."""

    def test_voice_api_transcribe(self):
        # Send simulated file bytes (100 bytes long)
        audio_bytes = b"A" * 100
        response = client.post(
            "/voice/transcribe",
            files={"file": ("test.wav", audio_bytes, "audio/wav")}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["text"] == "Hello Aevora"

    def test_voice_api_synthesize(self):
        response = client.post("/voice/synthesize?text=Hello")
        assert response.status_code == 200
        assert len(response.content) > 0
        # Media type should be audio
        assert "audio/" in response.headers["content-type"]

from fastapi import APIRouter, Depends, UploadFile, File, Response
from fastapi.responses import StreamingResponse
import io
from typing import Optional
from app.services.voice_engine import VoiceEngine


router = APIRouter()


def get_voice_engine() -> VoiceEngine:
    """Dependency injection helper for VoiceEngine."""
    return VoiceEngine()


@router.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    voice_engine: VoiceEngine = Depends(get_voice_engine)
):
    """
    Transcribe uploaded audio file into text.
    """
    import time
    start_time = time.time()
    audio_bytes = await file.read()
    read_time = time.time() - start_time
    print(f"[VOICE API] Received audio upload: filename={file.filename}, content_type={file.content_type}, size={len(audio_bytes)} bytes (Read in {read_time:.3f}s)")

    text = voice_engine.transcribe(audio_bytes)
    total_time = time.time() - start_time
    print(f"[VOICE API] Transcribed text: '{text}' (Total time: {total_time:.3f}s)")
    return {"text": text}


@router.post("/synthesize")
async def synthesize(
    text: str,
    voice: Optional[str] = None,
    rate: Optional[str] = None,
    pitch: Optional[str] = None,
    voice_engine: VoiceEngine = Depends(get_voice_engine)
):
    """
    Synthesize text into playable speech audio bytes.
    """
    audio_data = voice_engine.synthesize(text, voice=voice, rate=rate, pitch=pitch)
    
    # Improved media type detection (Fix for Task 1 stuttering)
    media_type = "audio/mpeg" # Default to mp3 for edge-tts

    if audio_data.startswith(b"RIFF"):
        media_type = "audio/wav"
    elif audio_data.startswith(b"FORM") or audio_data.startswith(b"AIFF"):
        # AIFF files start with FORM....AIFF
        media_type = "audio/x-aiff"
    elif audio_data.startswith(b"ID3") or (len(audio_data) > 2 and audio_data[0] == 0xff and (audio_data[1] & 0xe0) == 0xe0):
        media_type = "audio/mpeg"

    return StreamingResponse(io.BytesIO(audio_data), media_type=media_type)

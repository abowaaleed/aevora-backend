FROM python:3.12-slim

# System dependencies: ffmpeg lets pydub decode iPhone m4a audio for transcription
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies first (better layer caching)
COPY backend/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Pre-download the faster-whisper "base" model so voice transcription works
# immediately on cold start without a slow runtime download.
RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('Systran/faster-whisper-base')"

# Copy application code
COPY backend/ /app/

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Render injects $PORT; default to 8000 for local Docker runs
CMD uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}

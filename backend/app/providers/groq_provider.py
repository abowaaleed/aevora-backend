"""
Groq Provider — OpenAI-compatible API (text only).

Used as an automatic fallback for text chat and text summarization when
Gemini's quota/availability is exhausted. Activates once GROQ_API_KEY is set.
"""

import os
import json
import requests
from typing import List, Dict, Any, Iterator

from app.providers.base_provider import BaseProvider

GROQ_BASE_URL = "https://api.groq.com/openai/v1"
DEFAULT_GROQ_MODEL = "llama-3.3-70b-versatile"


class GroqProvider(BaseProvider):
    """
    Groq provider for fast open-source (Llama) inference.
    Text-only — cannot process images or audio.
    """

    def __init__(self, model: str = None, timeout: int = 90):
        self.api_key = os.getenv("GROQ_API_KEY", "").strip()
        self.model = model or os.getenv("GROQ_MODEL", DEFAULT_GROQ_MODEL)
        self.timeout = timeout
        self.api_url = f"{GROQ_BASE_URL}/chat/completions"
        self.available = bool(self.api_key)
        self.api_url_base = GROQ_BASE_URL

    def _headers(self) -> Dict[str, str]:
        return {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

    def _check_available(self):
        if not self.available:
            raise RuntimeError(
                "GROQ_API_KEY is not set. Add it to backend/.env to enable the Groq fallback."
            )

    def generate(self, prompt: str, **kwargs) -> str:
        """Non-streaming completion. Returns the full text."""
        self._check_available()
        messages = [{"role": "user", "content": prompt}]
        payload = {
            "model": self.model,
            "messages": messages,
            "temperature": 0.4,
            "max_tokens": kwargs.get("num_predict", 400),
            "stream": False,
        }
        resp = requests.post(
            self.api_url, headers=self._headers(), json=payload, timeout=self.timeout
        )
        resp.encoding = "utf-8"
        resp.raise_for_status()
        data = resp.json()
        try:
            return data["choices"][0]["message"]["content"]
        except (KeyError, IndexError):
            raise ValueError(f"Unexpected Groq response: {data}")

    def generate_with_messages(self, messages: List[Dict[str, Any]], **kwargs) -> str:
        """Non-streaming completion with a full message list (system + history)."""
        self._check_available()
        payload = {
            "model": self.model,
            "messages": messages,
            "temperature": kwargs.get("temperature", 0.4),
            "max_tokens": kwargs.get("max_tokens", 400),
            "stream": False,
        }
        resp = requests.post(
            self.api_url, headers=self._headers(), json=payload, timeout=self.timeout
        )
        resp.encoding = "utf-8"
        resp.raise_for_status()
        data = resp.json()
        try:
            return data["choices"][0]["message"]["content"]
        except (KeyError, IndexError):
            raise ValueError(f"Unexpected Groq response: {data}")

    def stream(self, messages: List[Dict[str, Any]], **kwargs) -> Iterator[str]:
        """
        Streaming completion. Yields text deltas as they arrive.
        """
        self._check_available()
        payload = {
            "model": self.model,
            "messages": messages,
            "temperature": kwargs.get("temperature", 0.4),
            "max_tokens": kwargs.get("max_tokens", 512),
            "stream": True,
        }
        with requests.post(
            self.api_url,
            headers=self._headers(),
            json=payload,
            timeout=self.timeout,
            stream=True,
        ) as resp:
            resp.encoding = "utf-8"
            resp.raise_for_status()
            for line in resp.iter_lines(decode_unicode=True):
                if not line or not line.startswith("data:"):
                    continue
                data = line[len("data:"):].strip()
                if data == "[DONE]":
                    break
                try:
                    chunk = json.loads(data)
                    delta = chunk["choices"][0]["delta"].get("content", "")
                    if delta:
                        yield delta
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue

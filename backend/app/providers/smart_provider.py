"""
Smart Provider — BaseProvider implementation used by the sync pipeline.

Tries Gemini first; on any error (e.g. quota 429) falls back to Groq for
text generation. Groq activates automatically once GROQ_API_KEY is set.
"""

from app.providers.base_provider import BaseProvider
from app.providers.gemini_provider import GeminiProvider
from app.providers.groq_provider import GroqProvider


class SmartProvider(BaseProvider):
    """Primary Gemini + fallback Groq for synchronous pipeline calls."""

    def __init__(self):
        self.primary = GeminiProvider()
        self.fallback = GroqProvider()
        self.model = self.primary.model
        self.api_url = self.primary.api_url

    def generate(self, prompt: str, **kwargs) -> str:
        try:
            return self.primary.generate(prompt, **kwargs)
        except Exception as e:
            print(f"[SMART PROVIDER] Gemini failed ({e}); falling back to Groq")
            if not self.fallback.available:
                raise
            return self.fallback.generate(prompt, **kwargs)

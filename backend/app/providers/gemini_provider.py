from .base_provider import BaseProvider
from app.services.gemini_service import GeminiService

class GeminiProvider(BaseProvider):
    """
    Google Gemini AI Provider implementation.
    """

    def __init__(self):
        self.service = GeminiService()
        self.model = "gemini-3.5-flash"
        self.api_url = "https://generativelanguage.googleapis.com"

    def generate(self, prompt: str, **kwargs) -> str:
        """
        Generate a response using Gemini 1.5 Flash.
        """
        # We use the sync-like call for the standard pipeline
        return self.service.generate_content_sync(prompt)

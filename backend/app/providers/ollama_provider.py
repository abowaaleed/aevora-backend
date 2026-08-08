"""
Ollama Provider — Optimized for Mustafeed (speed-first).

Reduced num_predict, optimized num_thread for CPU inference.
"""

import os
import requests
from app.providers.base_provider import BaseProvider


class OllamaProvider(BaseProvider):
    """
    Ollama provider for local AI inference — Mustafeed optimized.
    """

    def __init__(self, base_url: str = "http://localhost:11434", model: str = "qwen2.5:3b", timeout: int = 90):
        self.base_url = base_url
        self.model = model
        self.timeout = timeout
        self.api_url = f"{base_url}/api/generate"
        self.last_eval_count = 0
        # Auto-detect CPU thread count for num_thread optimization
        self._num_thread = min(os.cpu_count() or 4, 8)

    def generate(self, prompt: str, **kwargs) -> str:
        num_predict = kwargs.get("num_predict", 200)

        payload = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "keep_alive": "10m",
            "options": {
                "temperature": 0.3,
                "top_p": 0.9,
                "num_predict": num_predict,
                "num_thread": self._num_thread,
                "repeat_penalty": 1.1,
                "presence_penalty": 0.0,
                "frequency_penalty": 0.0,
            }
        }

        try:
            response = requests.post(
                self.api_url,
                json=payload,
                timeout=self.timeout
            )
            response.raise_for_status()
            data = response.json()

            if "response" not in data:
                raise ValueError("Invalid response from Ollama API: missing 'response' field")

            self.last_eval_count = data.get("eval_count", 0)
            return data["response"]

        except requests.Timeout:
            raise requests.RequestException(f"Ollama API request timed out after {self.timeout} seconds")
        except requests.ConnectionError:
            raise requests.RequestException(f"Failed to connect to Ollama at {self.base_url}. Ensure Ollama is running.")
        except requests.HTTPError as e:
            raise requests.RequestException(f"Ollama API returned HTTP error: {e}")
        except requests.JSONDecodeError:
            raise ValueError("Invalid JSON response from Ollama API")

import os
import json
import base64
from typing import List, Optional, AsyncGenerator

import httpx
from dotenv import load_dotenv

from app.core.user_context import PUBLIC_MODE, current_gemini_key

load_dotenv()

# 1. إعداد مفتاح الخادم (اختياري — النسخة العامة تعتمد على مفتاح كل مستخدم)
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

MODEL_NAME = "gemini-3.5-flash"
_REST_BASE = "https://generativelanguage.googleapis.com/v1beta/models"

# 2. تهيئة النموذج بإعدادات النظام الخاصة بإيفورا
SYSTEM_INSTRUCTION = """
أنت 'إيفورا (Evora)'، مساعد شخصي ذكي، سريع، ولبق.
تتحدث باللغة العربية بأسلوب واضح ومباشر.
إجاباتك مركزة ومفيدة دائماً.
"""


def _user_key() -> Optional[str]:
    return current_gemini_key()


def _server_key() -> Optional[str]:
    """مفتاح الخادم لا يُستعمل إطلاقاً في الوضع العام (حماية حصة الخادم)."""
    if PUBLIC_MODE:
        return None
    return GEMINI_API_KEY


class GeminiService:
    def __init__(self):
        self._model = None

    # ------------------------------------------------------------------
    # أداة مساعدة: REST (يُستعمل مفتاح المستخدم في النسخة العامة)
    # ------------------------------------------------------------------
    def _active_key(self) -> Optional[str]:
        """مفتاح Gemini الفعّال: مفتاح المستخدم أولاً ثم مفتاح الخادم."""
        return _user_key() or _server_key()

    def _ensure_sdk(self):
        if self._model is None:
            import google.generativeai as genai
            if not _server_key():
                raise RuntimeError(
                    "لا يوجد مفتاح Gemini على الخادم، والمستخدم لم يقدّم مفتاحاً."
                )
            genai.configure(api_key=_server_key())
            self._model = genai.GenerativeModel(
                model_name=MODEL_NAME,
                system_instruction=SYSTEM_INSTRUCTION,
            )
        return self._model

    def _rest_headers(self, key: str) -> dict:
        return {"Content-Type": "application/json"}

    def _rest_url(self, key: str, stream: bool) -> str:
        suffix = "streamGenerateContent?alt=sse" if stream else "generateContent"
        return f"{_REST_BASE}/{MODEL_NAME}:{suffix}&key={key}"

    def _build_contents(self, prompt: str, history: List[dict]) -> List[dict]:
        contents = []
        for turn in (history or []):
            role = "model" if turn.get("role") == "model" else "user"
            contents.append({"role": role, "parts": [{"text": turn.get("content", turn.get("parts", ""))}]})
        contents.append({"role": "user", "parts": [{"text": prompt}]})
        return contents

    async def _rest_stream(self, prompt: str, history: List[dict], system_instruction: str, key: str):
        payload = {"contents": self._build_contents(prompt, history)}
        if system_instruction:
            payload["system_instruction"] = {"parts": [{"text": system_instruction}]}
        timeout = httpx.Timeout(120.0, connect=30.0)
        async with httpx.AsyncClient(timeout=timeout) as client:
            async with client.stream(
                "POST", self._rest_url(key, stream=True), headers=self._rest_headers(key), json=payload
            ) as resp:
                if resp.status_code != 200:
                    body = await resp.aread()
                    detail = ""
                    try:
                        obj = json.loads(body)
                        detail = (obj.get("error") or {}).get("message", "")
                    except Exception:
                        pass
                    raise RuntimeError(
                        f"مزود Gemini رفض المفتاح أو انتهت حصتك (HTTP {resp.status_code}). "
                        f"{detail}"
                    )
                async for line in resp.aiter_lines():
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if not data or data == "[DONE]":
                        continue
                    try:
                        obj = json.loads(data)
                    except Exception:
                        continue
                    candidates = obj.get("candidates") or []
                    for cand in candidates:
                        content = cand.get("content") or {}
                        for part in content.get("parts") or []:
                            text = part.get("text")
                            if text:
                                yield text

    def _rest_generate(self, contents: List[dict], key: str, system_instruction: str = None) -> str:
        payload = {"contents": contents}
        if system_instruction:
            payload["system_instruction"] = {"parts": [{"text": system_instruction}]}
        resp = httpx.post(
            self._rest_url(key, stream=False),
            headers=self._rest_headers(key),
            json=payload,
            timeout=120.0,
        )
        if resp.status_code != 200:
            raise RuntimeError(f"Gemini REST error {resp.status_code}: {resp.text[:300]}")
        obj = resp.json()
        text = ""
        for cand in obj.get("candidates") or []:
            for part in (cand.get("content") or {}).get("parts") or []:
                text += part.get("text") or ""
        return text.strip()

    # ------------------------------------------------------------------
    # النداءات العامة
    # ------------------------------------------------------------------
    async def stream_evora_response(
        self,
        prompt: str,
        history: List[dict] = None,
        knowledge: str = None,
        system_instruction: str = None,
    ) -> AsyncGenerator[str, None]:
        """
        دالة المحادثة النصية مع Streaming
        عند وجود معرفة من مستندات مرفوعة (RAG) تُحقن في الرسالة ليعتمد عليها النموذج.
        """
        if knowledge:
            prompt = (
                "إليك معلومات مأخوذة من مستندات مرفوعة من قبل المستخدم. "
                "أجب عن سؤال المستخدم بالاعتماد على هذه المعلومات حصراً، "
                "وإن لم تكن الإجابة موجودة فيها فقل ذلك بوضوح دون اختلاق بيانات.\n\n"
                f"المعلومات:\n{knowledge}\n\n"
                f"سؤال المستخدم: {prompt}"
            )

        user_key = _user_key()
        if user_key:
            async for chunk in self._rest_stream(
                prompt, history, system_instruction or SYSTEM_INSTRUCTION, user_key
            ):
                yield chunk
            return

        model = self._ensure_sdk()
        if system_instruction:
            import google.generativeai as genai
            model = genai.GenerativeModel(
                model_name=MODEL_NAME,
                system_instruction=system_instruction,
            )
        chat = model.start_chat(history=history or [])
        response = chat.send_message(prompt, stream=True)
        for chunk in response:
            if chunk.text:
                yield chunk.text

    def generate_content_sync(self, contents: List[any], history: List[dict] = None) -> str:
        """
        Non-streaming sync version for internal pipeline usage if needed.
        """
        user_key = _user_key()
        if user_key:
            prompt = contents[0] if isinstance(contents, list) and contents else str(contents)
            built = self._build_contents(str(prompt), history)
            return self._rest_generate(built, user_key, SYSTEM_INSTRUCTION)
        model = self._ensure_sdk()
        chat = model.start_chat(history=history or [])
        response = chat.send_message(contents)
        return response.text

    def transcribe_audio(self, audio_bytes: bytes, mime: str) -> str:
        """
        Speech-to-Text عبر Gemini. يستعمل مفتاح المستخدم عند وجوده،
        وإلا مفتاح الخادم عبر الـ SDK.
        """
        prompt = (
            "Transcribe this audio exactly as spoken. "
            "Output ONLY the transcribed text, with no extra words or punctuation changes."
        )
        user_key = _user_key()
        if user_key:
            contents = [
                {
                    "parts": [
                        {"inline_data": {"mime_type": mime, "data": base64.b64encode(audio_bytes).decode()}},
                        {"text": prompt},
                    ]
                }
            ]
            return self._rest_generate(contents, user_key)
        model = self._ensure_sdk()
        response = model.generate_content(
            [{"mime_type": mime, "data": audio_bytes}, prompt]
        )
        return (response.text or "").strip()

    async def process_pdf_and_summarize(
        self, pdf_file_path: str,
        custom_prompt: str = "قم بتلخيص هذا المستند في نقاط رئيسية واضحة ومحددة."
    ) -> AsyncGenerator[str, None]:
        """
        دالة معالجة وتلخيص ملفات PDF
        """
        user_key = _user_key()
        if user_key:
            with open(pdf_file_path, "rb") as f:
                data = base64.b64encode(f.read()).decode()
            contents = [
                {
                    "parts": [
                        {"inline_data": {"mime_type": "application/pdf", "data": data}},
                        {"text": custom_prompt},
                    ]
                }
            ]
            text = self._rest_generate(contents, user_key, SYSTEM_INSTRUCTION)
            if text:
                yield text
            return

        import google.generativeai as genai
        model = self._ensure_sdk()
        uploaded_file = genai.upload_file(path=pdf_file_path)

        response = model.generate_content(
            [uploaded_file, custom_prompt],
            stream=True
        )

        for chunk in response:
            if chunk.text:
                yield chunk.text

        # تنظيف الملف المرفوع بعد الانتهاء
        try:
            genai.delete_file(uploaded_file.name)
        except Exception as e:
            print(f"Warning: Failed to delete remote file {uploaded_file.name}: {e}")

    def extract_text_from_image(self, image_bytes: bytes, mime_type: str) -> str:
        """
        Send an image to Gemini (vision) and extract all text/information in it.
        Used by the RAG pipeline to index image uploads.
        """
        prompt = (
            "استخرج بدقة كل النصوص والمعلومات المكتوبة أو الظاهرة في هذه الصورة "
            "باللغة الأصلية الموجودة فيها، ورتبها بنفس ترتيبها. "
            "لا تضف أي شرح أو تعليق، وأعد المحتوى المستخرج فقط."
        )
        user_key = _user_key()
        if user_key:
            contents = [
                {
                    "parts": [
                        {"inline_data": {"mime_type": mime_type, "data": base64.b64encode(image_bytes).decode()}},
                        {"text": prompt},
                    ]
                }
            ]
            return self._rest_generate(contents, user_key)
        model = self._ensure_sdk()
        response = model.generate_content(
            [{"mime_type": mime_type, "data": image_bytes}, prompt]
        )
        return (response.text or "").strip()

    def extract_text_from_pdf(self, pdf_path: str) -> str:
        """
        Send a PDF to Gemini for full analysis/extraction.
        Used as a fallback for scanned PDFs where text extraction yields nothing.
        """
        user_key = _user_key()
        if user_key:
            with open(pdf_path, "rb") as f:
                data = base64.b64encode(f.read()).decode()
            prompt = (
                "استخرج بدقة كل النصوص والمعلومات الموجودة في هذا الملف باللغة الأصلية "
                "ورتبها بنفس الترتيب. لا تضف أي شرح أو تعليق، وأعد المحتوى المستخرج فقط."
            )
            contents = [
                {
                    "parts": [
                        {"inline_data": {"mime_type": "application/pdf", "data": data}},
                        {"text": prompt},
                    ]
                }
            ]
            return self._rest_generate(contents, user_key)

        import google.generativeai as genai
        model = self._ensure_sdk()
        uploaded_file = genai.upload_file(path=pdf_path)
        try:
            prompt = (
                "استخرج بدقة كل النصوص والمعلومات الموجودة في هذا الملف باللغة الأصلية "
                "ورتبها بنفس الترتيب. لا تضف أي شرح أو تعليق، وأعد المحتوى المستخرج فقط."
            )
            response = model.generate_content([uploaded_file, prompt])
            return (response.text or "").strip()
        finally:
            try:
                genai.delete_file(uploaded_file.name)
            except Exception:
                pass

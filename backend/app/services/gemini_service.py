import os
import google.generativeai as genai
from dotenv import load_dotenv
from typing import List, Optional, AsyncGenerator

load_dotenv()

# 1. إعداد المفتاح
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    raise RuntimeError(
        "GEMINI_API_KEY is not set. Please set it in backend/.env "
        "or in the platform environment variables."
    )

genai.configure(api_key=GEMINI_API_KEY)

# 2. تهيئة النموذج بإعدادات النظام الخاصة بإيفورا
SYSTEM_INSTRUCTION = """
أنت 'إيفورا (Evora)'، مساعد شخصي ذكي، سريع، ولبق.
تتحدث باللغة العربية بأسلوب واضح ومباشر.
إجاباتك مركزة ومفيدة دائماً.
"""

class GeminiService:
    def __init__(self):
        self.model = genai.GenerativeModel(
            model_name="gemini-3.5-flash",
            system_instruction=SYSTEM_INSTRUCTION
        )

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
        model = self.model
        if system_instruction:
            model = genai.GenerativeModel(
                model_name="gemini-3.5-flash",
                system_instruction=system_instruction,
            )

        if knowledge:
            prompt = (
                "إليك معلومات مأخوذة من مستندات مرفوعة من قبل المستخدم. "
                "أجب عن سؤال المستخدم بالاعتماد على هذه المعلومات حصراً، "
                "وإن لم تكن الإجابة موجودة فيها فقل ذلك بوضوح دون اختلاق بيانات.\n\n"
                f"المعلومات:\n{knowledge}\n\n"
                f"سؤال المستخدم: {prompt}"
            )

        chat = model.start_chat(history=history or [])
        response = chat.send_message(prompt, stream=True)
        for chunk in response:
            if chunk.text:
                yield chunk.text

    async def process_pdf_and_summarize(self, pdf_file_path: str, custom_prompt: str = "قم بتلخيص هذا المستند في نقاط رئيسية واضحة ومحددة.") -> AsyncGenerator[str, None]:
        """
        دالة معالجة وتلخيص ملفات PDF
        """
        uploaded_file = genai.upload_file(path=pdf_file_path)

        response = self.model.generate_content(
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

    def generate_content_sync(self, contents: List[any], history: List[dict] = None) -> str:
        """
        Non-streaming sync version for internal pipeline usage if needed.
        """
        chat = self.model.start_chat(history=history or [])
        response = chat.send_message(contents)
        return response.text

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
        response = self.model.generate_content(
            [{"mime_type": mime_type, "data": image_bytes}, prompt]
        )
        return (response.text or "").strip()

    def extract_text_from_pdf(self, pdf_path: str) -> str:
        """
        Send a PDF to Gemini for full analysis/extraction.
        Used as a fallback for scanned PDFs where text extraction yields nothing.
        """
        uploaded_file = genai.upload_file(path=pdf_path)
        try:
            prompt = (
                "استخرج بدقة كل النصوص والمعلومات الموجودة في هذا الملف باللغة الأصلية "
                "ورتبها بنفس الترتيب. لا تضف أي شرح أو تعليق، وأعد المحتوى المستخرج فقط."
            )
            response = self.model.generate_content([uploaded_file, prompt])
            return (response.text or "").strip()
        finally:
            try:
                genai.delete_file(uploaded_file.name)
            except Exception:
                pass

"""
Smart Router — "الموزّع الذكي".

Primary:  Gemini (text + vision + audio).
Fallback: Groq (text only) — used automatically when Gemini quota is
exhausted or Gemini fails before producing any output.

Activates as soon as GROQ_API_KEY is set in the environment.
"""

import asyncio
from typing import AsyncGenerator, Optional

from app.providers.gemini_provider import GeminiProvider
from app.providers.groq_provider import GroqProvider

DEFAULT_SYSTEM = (
    "أنت 'إيفورا (Evora)'، مساعد شخصي ذكي، سريع، ولبق. "
    "تتحدث باللغة العربية بأسلوب واضح ومباشر. إجاباتك مركزة ومفيدة دائماً.\n"
    "عند إعطائك معلومات من المستندات: انقل الأرقام والقيم والعناوين حرفياً كما وردت، "
    "ولا تغيّر أو تختلق أو تدمج أي رقم. إذا لم توجد المعلومة المطلوبة في النص المعطى، "
    "قل بوضوح: 'لا توجد معلومات كافية في المستندات المرفوعة'."
)

_KNOWLEDGE_WRAPPER = (
    "إليك معلومات مأخوذة من مستندات مرفوعة من قبل المستخدم. "
    "أجب عن سؤال المستخدم بالاعتماد على هذه المعلومات حصراً. "
    "انقل الأرقام والقيم حرفياً كما وردت في المعلومات — لا تغيّر أو تختلق أي رقم. "
    "لا تخلط معلومات أقسام مختلفة. "
    "إن لم تكن الإجابة موجودة في هذه المعلومات فقل بوضوح دون اختلاق بيانات: "
    "'لا توجد معلومات كافية في المستندات المرفوعة'.\n\n"
    "المعلومات:\n{knowledge}\n\n"
    "سؤال المستخدم: {prompt}"
)


class SmartRouter:
    """Routes requests to Gemini first, then falls back to Groq for text."""

    def __init__(self):
        self.gemini = GeminiProvider()
        self.groq = GroqProvider()

    def groq_enabled(self) -> bool:
        return self.groq.available

    def _groq_messages(self, prompt: str, knowledge: Optional[str], system_instruction: Optional[str]) -> list:
        system = system_instruction or DEFAULT_SYSTEM
        if knowledge:
            content = _KNOWLEDGE_WRAPPER.format(prompt=prompt, knowledge=knowledge)
        else:
            content = prompt
        return [
            {"role": "system", "content": system},
            {"role": "user", "content": content},
        ]

    async def stream(
        self,
        prompt: str,
        knowledge: Optional[str] = None,
        system_instruction: Optional[str] = None,
    ) -> AsyncGenerator[str, None]:
        """
        Stream a reply. Tries Gemini first; if Gemini fails before yielding any
        output (e.g. 429 quota exceeded), falls back to streaming via Groq.
        """
        produced_any = False
        try:
            gem = self.gemini.service.stream_evora_response(
                prompt, knowledge=knowledge, system_instruction=system_instruction
            )
            async for chunk in gem:
                produced_any = True
                yield chunk
            return
        except Exception as e:
            if produced_any:
                # Failed mid-stream after partial output — surface the error.
                raise
            print(f"[SMART ROUTER] Gemini failed before output ({e}); trying Groq")
            if not self.groq.available:
                raise
            messages = self._groq_messages(prompt, knowledge, system_instruction)

            def _run_groq():
                return list(self.groq.stream(messages))

            try:
                chunks = await asyncio.to_thread(_run_groq)
            except Exception as ge:
                print(f"[SMART ROUTER] Groq fallback also failed: {ge}")
                raise
            for c in chunks:
                yield c

    def summarize_text(self, text: str, language: str = "ar") -> str:
        """
        Summarize extracted text. Gemini first, then Groq fallback.
        Returns a plain-text summary string (not streamed).
        """
        prompt = (
            "قم بتلخيص هذا المحتوى في نقاط رئيسية واضحة ومحددة، "
            "مع الحفاظ على الأرقام والمعلومات المهمة.\n\n"
            f"المحتوى:\n{text}"
        )
        try:
            return self.gemini.service.generate_content_sync(prompt)
        except Exception as e:
            print(f"[SMART ROUTER] Gemini summarization failed ({e}); trying Groq")
            if not self.groq.available:
                raise
            try:
                return self.groq.generate(prompt, num_predict=600)
            except Exception as ge:
                print(f"[SMART ROUTER] Groq summarization failed: {ge}")
                raise

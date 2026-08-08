import json
import re
import asyncio
from app.runtime.stages.base_validator import ResponseValidator
from app.runtime.stages.models import ValidationResult, ValidationVerdict
from app.services.ai_engine import AIEngine

JUDGE_PROMPT_TEMPLATE = (
    "[SYSTEM: Independent Judge]\n"
    "راجع الإجابة التالية بدقة كمراقب مستقل، لا تجب على السؤال بنفسك.\n"
    "السؤال: {question}\n"
    "الإجابة: {answer}\n"
    "السياق المتاح: {context}\n\n"
    "أجب فقط بصيغة JSON:\n"
    "{{\n"
    '  "verdict": "approved|uncertain|rejected",\n'
    '  "reason": "...",\n'
    '  "confidence": 0.0-1.0\n'
    "}}\n\n"
    "ارفض فقط إذا: تناقض علمي واضح، معلومة أو اسم غير موجود بالسياق، تناقض مع المحادثة."
)

class JudgeValidator(ResponseValidator):
    """
    LLM-as-judge response validator using a separate LLM call.
    """
    
    def __init__(self, ai_engine: AIEngine, timeout: float = 30.0):
        self.ai_engine = ai_engine
        self.timeout = timeout

    async def validate(self, question: str, answer: str, context: dict) -> ValidationResult:
        context_str = json.dumps(context, ensure_ascii=False)
        # Optimized Judge Prompt: Shorter, more direct to save tokens and inference time
        prompt = (
            "[SYSTEM: Quick Judge]\n"
            f"Check if the answer correctly addresses: '{question}'\n"
            f"Context: {context_str}\n"
            f"Response: {answer}\n"
            "JSON ONLY: {\"verdict\": \"approved|uncertain|rejected\", \"reason\": \"...\", \"confidence\": 0-1}"
        )
        
        try:
            # Execute LLM call in a separate thread with a realistic CPU timeout
            loop = asyncio.get_running_loop()
            # Wrap the generator call in a lambda to avoid passing keyword arguments to run_in_executor
            raw_res = await asyncio.wait_for(
                loop.run_in_executor(None, lambda: self.ai_engine.generate_with_prompt(prompt, num_predict=60)),
                timeout=self.timeout
            )
            raw_res = raw_res.strip()
            print(f"[JUDGE RAW RESPONSE]:\n{raw_res}")

            # Defensive JSON parsing
            match = re.search(r"\{.*\}", raw_res, re.DOTALL)
            if not match:
                raise ValueError("No JSON object found in response")
                
            parsed = json.loads(match.group(0))
            
            # Map string to ValidationVerdict enum safely
            verdict_str = parsed.get("verdict", "uncertain").strip().lower()
            verdict = ValidationVerdict.UNCERTAIN
            if verdict_str == "approved":
                verdict = ValidationVerdict.APPROVED
            elif verdict_str == "rejected":
                verdict = ValidationVerdict.REJECTED
                
            return ValidationResult(
                verdict=verdict,
                reason=parsed.get("reason", "No reason provided"),
                confidence=float(parsed.get("confidence", 0.5))
            )
            
        except asyncio.TimeoutError:
            print("[JUDGE] Call timed out. Returning uncertain fallback.")
            return ValidationResult(
                verdict=ValidationVerdict.UNCERTAIN,
                reason="judge_unavailable",
                confidence=0.0
            )
        except Exception as e:
            print(f"[JUDGE] Error during verification: {e}. Returning uncertain fallback.")
            return ValidationResult(
                verdict=ValidationVerdict.UNCERTAIN,
                reason="judge_unavailable",
                confidence=0.0
            )

import re
from app.runtime.stages.base_validator import ResponseValidator
from app.runtime.stages.models import ValidationResult, ValidationVerdict

class RuleValidator(ResponseValidator):
    """
    Fast, deterministic rule-based response validator.
    """
    
    async def validate(self, question: str, answer: str, context: dict) -> ValidationResult:
        # 1. Biology and common-sense contradictions
        relevant_knowledge = context.get("relevant_knowledge", "") or ""
        k_lower = relevant_knowledge.lower()
        r_lower = answer.lower()
        
        # Mammal birth vs laying eggs contradiction
        if "تلد ولا تبيض" in k_lower or "لا يبيض" in k_lower:
            if ("يبيض" in r_lower or "تضع البيض" in r_lower) and ("لا يبيض" not in r_lower and "لا تبيض" not in r_lower and "ليس يبيض" not in r_lower):
                return ValidationResult(
                    verdict=ValidationVerdict.REJECTED,
                    reason="تناقض علمي: الثدييات تلد ولا تبيض.",
                    confidence=1.0
                )
                
        # Fingers count contradiction
        if "خمسة أصابع" in k_lower or "خمس أصابع" in k_lower:
            if any(num in r_lower for num in ["أربعة", "اربعة", "أربع", "عشرة", "عشر"]):
                # check if there's no negation
                negations = ["ليس", "لا", "بدون"]
                if not any(neg in r_lower for neg in negations):
                    return ValidationResult(
                        verdict=ValidationVerdict.REJECTED,
                        reason="تناقض علمي: عدد أصابع اليد خمسة وليس رقماً آخر.",
                        confidence=1.0
                    )

        # 3. NUMERIC HALLUCINATION GUARD
        # If the query asks for aggregation/counting/filtering, and the response
        # contains a concrete number NOT present in the source, reject it.
        # This catches LLM fabrications like "206" or "93 و 53" when those
        # numbers don't appear in the document content.
        from app.rag.document_service import is_aggregation_query
        if is_aggregation_query(question) and relevant_knowledge:
            # Extract all numbers from the response (Arabic + Western digits)
            response_numbers = set(re.findall(r'\d+', answer))
            # Extract all numbers from the source content
            source_numbers = set(re.findall(r'\d+', relevant_knowledge))

            # Filter out trivial numbers (single digits, years, phone-like)
            meaningful_response_nums = {n for n in response_numbers if int(n) > 10}
            meaningful_source_nums = {n for n in source_numbers if int(n) > 10}

            # If the response contains meaningful numbers NOT in the source, reject
            fabricated = meaningful_response_nums - meaningful_source_nums
            if fabricated and meaningful_response_nums:
                # Allow single-digit counts (1-9) as they could be legitimate small counts
                serious_fabrication = {n for n in fabricated if int(n) > 9}
                if serious_fabrication:
                    return ValidationResult(
                        verdict=ValidationVerdict.REJECTED,
                        reason=f"أرقام مختلقة: الإجابة تحتوي على أرقام ({', '.join(serious_fabrication)}) غير موجودة في مصادر البيانات.",
                        confidence=1.0
                    )
                    
        # 2. Memory / context mismatch (e.g. wrong identity facts)
        user_msg = context.get("user_message", "") or ""
        selected_mem = context.get("selected_memory", "") or ""
        retrieved_mems = context.get("retrieved_memories", []) or []
        brain_context = context.get("user_brain_context", "") or ""
        
        allowed_context = user_msg + " " + (context.get("relevant_knowledge", "") or "") + " " + selected_mem + " " + " ".join(retrieved_mems) + " " + brain_context
        
        # Check personal identity mismatch
        critical_entities = ["ناصر", "القصيم", "الهلال", "أيفورا", "صالح", "علي", "محمد", "Aevora"]
        for entity in critical_entities:
            if entity in answer and entity not in allowed_context:
                return ValidationResult(
                    verdict=ValidationVerdict.REJECTED,
                    reason=f"معلومة شخصية غير صحيحة: ذكر '{entity}' وهي غير موجودة بالسياق.",
                    confidence=1.0
                )
                
        return ValidationResult(
            verdict=ValidationVerdict.APPROVED,
            reason="جميع القواعد المحددة مرت بنجاح.",
            confidence=1.0
        )

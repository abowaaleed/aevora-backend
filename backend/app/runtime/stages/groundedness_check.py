"""
Lightweight Groundedness Check Stage.

Rule-based validation only — no LLM calls.
Checks if the response is traceable to retrieved content.
"""

import re
from ..task import Stage
from ..types import PipelineContext, StageStatus


class GroundednessCheckStage(Stage):
    """
    Lightweight rule-based groundedness check.
    
    Validates that the AI response is grounded in the retrieved document content
    without making additional LLM calls. This replaces the heavy LLM-based
    response_validation stage.
    """

    def __init__(self):
        super().__init__("groundedness_check")

    def execute(self, context: PipelineContext):
        if context.ai_response is None:
            return self._create_result(
                status=StageStatus.SKIPPED,
                output="No response to validate"
            )

        response = context.ai_response
        knowledge = context.relevant_knowledge or ""

        # If no documents were retrieved, skip validation
        if not knowledge or knowledge.strip() == "":
            return self._create_result(
                status=StageStatus.COMPLETED,
                output="No documents to validate against"
            )

        # Check 1: Detect hallucinated numbers (>= 10 not found in source)
        response_numbers = set(re.findall(r'\b\d{2,}\b', response))
        knowledge_numbers = set(re.findall(r'\b\d{2,}\b', knowledge))
        
        hallucinated_numbers = response_numbers - knowledge_numbers
        if hallucinated_numbers:
            print(f"[GROUNDEDNESS] Warning: Response contains numbers not in source: {hallucinated_numbers}")

        # Check 2: Check for common refusal patterns (good sign of grounding)
        refusal_patterns = [
            "لا توجد معلومات كافية",
            "لا أستطيع الإجابة",
            "غير موجود في",
            "لا توجد بيانات",
        ]
        is_refusal = any(p in response for p in refusal_patterns)

        # Check 3: Check if response is very short (likely a clean answer)
        is_short = len(response.split()) < 30

        # Check 4: Check for potential fabrication markers
        fabrication_markers = [
            "بحسب دراسات",
            "أكدت الدراسات",
            "تشير الأبحاث",
            "من المعروف علمياً",
        ]
        has_fabrication = any(m in response for m in fabrication_markers)

        status = StageStatus.COMPLETED
        output = "Groundedness check passed"

        if has_fabrication:
            print("[GROUNDEDNESS] Warning: Response may contain fabricated claims")
            output = "Warning: potential fabrication detected"

        if hallucinated_numbers and not is_refusal:
            print(f"[GROUNDEDNESS] Warning: {len(hallucinated_numbers)} hallucinated numbers detected")

        return self._create_result(
            status=status,
            output=output
        )

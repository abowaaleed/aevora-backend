from app.runtime.stages.base_validator import ResponseValidator
from app.runtime.stages.models import ValidationResult, ValidationVerdict

class CompositeValidator(ResponseValidator):
    """
    Composite response validator orchestrating rule-based and LLM-as-judge validation layers.
    """
    
    def __init__(self, rule_validator: ResponseValidator, judge_validator: ResponseValidator):
        self.rule_validator = rule_validator
        self.judge_validator = judge_validator

    async def validate(self, question: str, answer: str, context: dict) -> ValidationResult:
        # Layer 1: Rule-based validator
        rule_res = await self.rule_validator.validate(question, answer, context)
        if rule_res.verdict == ValidationVerdict.REJECTED:
            print(f"[COMPOSITE VALIDATOR] Layer 1 Rejected: {rule_res.reason}")
            return rule_res
            
        # Layer 2: LLM-as-judge validator
        import os
        if os.getenv("ENABLE_JUDGE_VALIDATION", "true").lower() != "true":
            print("[COMPOSITE VALIDATOR] Layer 2 Judge Validator is disabled via feature flag. Bypassing.")
            return ValidationResult(verdict=ValidationVerdict.APPROVED, reason="Bypassed by feature flag", confidence=1.0)
            
        print("[COMPOSITE VALIDATOR] Layer 1 Passed. Proceeding to Layer 2 Judge Validator.")
        return await self.judge_validator.validate(question, answer, context)

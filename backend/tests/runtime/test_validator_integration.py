import pytest
from unittest.mock import MagicMock, AsyncMock
from app.runtime.types import PipelineContext, RuntimeRequest
from app.runtime.stages.validator import ResponseValidationStage
from app.runtime.stages.models import ValidationResult, ValidationVerdict
from app.services.ai_engine import AIEngine

@pytest.mark.asyncio
async def test_validator_pipeline_integration_hallucination():
    import os
    os.environ["ENABLE_JUDGE_VALIDATION"] = "true"
    # 1. Setup mock AI engine
    ai_engine = MagicMock(spec=AIEngine)
    
    call_sequence = []
    
    def mock_generate_with_prompt(prompt):
        if "Logical & Factual Verification" in prompt:
            call_sequence.append("self-critique")
            # Self critique mistakenly approves the bad answer
            return "CONFIDENCE: 90\nSTATUS: VALID\nREASON: All correct"
        elif "Independent Judge" in prompt:
            call_sequence.append("judge")
            # Independent judge catches the error and rejects it
            return '{"verdict": "rejected", "reason": "الأسد لا يبيض", "confidence": 0.95}'
        elif "REFINEMENT REQUIRED" in prompt:
            call_sequence.append("refinement")
            # Refinement returns corrected answer
            return "الأسد من الثدييات التي تلد ولا تبيض."
        else:
            call_sequence.append("other")
            return "Default response"
            
    ai_engine.generate_with_prompt.side_effect = mock_generate_with_prompt
    
    # 2. Setup mock validator instances
    from app.runtime.stages.rule_validator import RuleValidator
    from app.runtime.stages.judge_validator import JudgeValidator
    from app.runtime.stages.composite_validator import CompositeValidator
    
    rule_validator = RuleValidator()
    judge_validator = JudgeValidator(ai_engine)
    composite = CompositeValidator(rule_validator, judge_validator)
    
    stage = ResponseValidationStage(ai_engine, validator=composite)
    
    # 3. Setup context with a hallucinated response
    req = RuntimeRequest(
        user_message="لماذا الأسد لا يلد؟",
        session_id="test_session",
        user_id="test_user"
    )
    context = PipelineContext(request=req)
    context.ai_response = "الأسد لا يلد لأنه ذكر ولكنه يبيض."
    context.relevant_knowledge = ""
    
    # 4. Execute stage
    res = stage.execute(context)
    
    # 5. Assertions
    # Verify the sequence of calls:
    # - First self-critique loop starts
    # - Self-critique generates verdict (approves it)
    # - Judge validator runs (rejects it)
    # - Loop sees invalid result and runs refinement
    # - Second attempt starts: self critique runs on refined answer
    # - Self critique approves it
    # - Judge runs on refined answer
    # - Judge approves it
    
    assert len(call_sequence) >= 3
    assert call_sequence[0] == "self-critique"
    assert call_sequence[1] == "judge"
    assert call_sequence[2] == "refinement"
    
    # Ensure the final corrected response is saved
    assert context.ai_response != "الأسد لا يلد لأنه ذكر ولكنه يبيض."

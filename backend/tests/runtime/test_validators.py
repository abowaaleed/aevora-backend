import pytest
import asyncio
from unittest.mock import MagicMock
from app.runtime.stages.models import ValidationVerdict, ValidationResult
from app.runtime.stages.rule_validator import RuleValidator
from app.runtime.stages.judge_validator import JudgeValidator
from app.runtime.stages.composite_validator import CompositeValidator

# =====================================================================
# Unit Tests for RuleValidator
# =====================================================================

@pytest.mark.asyncio
async def test_rule_validator_correct():
    validator = RuleValidator()
    context = {
        "relevant_knowledge": "الأسود من الثدييات التي تلد ولا تبيض.",
        "user_message": "لماذا الأسد لا يبيض؟",
        "retrieved_memories": []
    }
    answer = "الأسد لا يبيض لأنه يلد."
    res = await validator.validate("لماذا الأسد لا يبيض؟", answer, context)
    assert res.verdict == ValidationVerdict.APPROVED
    assert res.confidence == 1.0

@pytest.mark.asyncio
async def test_rule_validator_biology_contradiction():
    validator = RuleValidator()
    context = {
        "relevant_knowledge": "الأسود من الثدييات التي تلد ولا تبيض.",
        "user_message": "لماذا الأسد لا يبيض؟",
    }
    answer = "الأسود تضع البيض في الغابة."
    res = await validator.validate("لماذا الأسد لا يبيض؟", answer, context)
    assert res.verdict == ValidationVerdict.REJECTED
    assert "تلد ولا تبيض" in res.reason

@pytest.mark.asyncio
async def test_rule_validator_name_mismatch():
    validator = RuleValidator()
    context = {
        "user_message": "ما اسمي؟",
        "selected_memory": "الاسم: ناصر"
    }
    answer = "اسمك هو صالح."
    res = await validator.validate("ما اسمي؟", answer, context)
    assert res.verdict == ValidationVerdict.REJECTED
    assert "صالح" in res.reason

@pytest.mark.asyncio
async def test_rule_validator_empty_context():
    validator = RuleValidator()
    context = {}
    answer = "الأسد حيوان قوي."
    res = await validator.validate("سؤال", answer, context)
    assert res.verdict == ValidationVerdict.APPROVED

@pytest.mark.asyncio
async def test_rule_validator_malformed():
    validator = RuleValidator()
    res = await validator.validate("", "", {})
    assert res.verdict == ValidationVerdict.APPROVED

# =====================================================================
# Unit Tests for JudgeValidator
# =====================================================================

@pytest.mark.asyncio
async def test_judge_validator_approved():
    import os
    os.environ["ENABLE_JUDGE_VALIDATION"] = "true"
    ai_engine = MagicMock()
    ai_engine.generate_with_prompt.return_value = '{"verdict": "approved", "reason": "Accurate fact", "confidence": 0.95}'
    
    validator = JudgeValidator(ai_engine)
    res = await validator.validate("Q", "A", {})
    assert res.verdict == ValidationVerdict.APPROVED
    assert res.confidence == 0.95
    assert res.reason == "Accurate fact"

@pytest.mark.asyncio
async def test_judge_validator_rejected():
    ai_engine = MagicMock()
    ai_engine.generate_with_prompt.return_value = '{"verdict": "rejected", "reason": "Incorrect name", "confidence": 0.9}'
    
    validator = JudgeValidator(ai_engine)
    res = await validator.validate("Q", "A", {})
    assert res.verdict == ValidationVerdict.REJECTED
    assert res.confidence == 0.9
    assert res.reason == "Incorrect name"

@pytest.mark.asyncio
async def test_judge_validator_malformed_json():
    ai_engine = MagicMock()
    ai_engine.generate_with_prompt.return_value = 'random gibberish not json'
    
    validator = JudgeValidator(ai_engine)
    res = await validator.validate("Q", "A", {})
    assert res.verdict == ValidationVerdict.UNCERTAIN
    assert res.reason == "judge_unavailable"

@pytest.mark.asyncio
async def test_judge_validator_timeout():
    ai_engine = MagicMock()
    
    def slow_generate(prompt):
        # Sleep for a long time to cause timeout
        import time
        time.sleep(2)
        return '{"verdict": "approved", "reason": "Accurate fact", "confidence": 0.95}'
        
    ai_engine.generate_with_prompt.side_effect = slow_generate
    
    # Use a tiny timeout of 0.2 seconds to guarantee triggering timeout fallback
    validator = JudgeValidator(ai_engine, timeout=0.2)
    res = await validator.validate("Q", "A", {})
    assert res.verdict == ValidationVerdict.UNCERTAIN
    assert res.reason == "judge_unavailable"

# =====================================================================
# Unit Tests for CompositeValidator
# =====================================================================

@pytest.mark.asyncio
async def test_composite_validator_layer1_rejected():
    from unittest.mock import AsyncMock
    rule_val = MagicMock()
    rule_val.validate = AsyncMock(return_value=ValidationResult(ValidationVerdict.REJECTED, "rule failed", 1.0))
    
    judge_val = MagicMock()
    
    comp = CompositeValidator(rule_val, judge_val)
    res = await comp.validate("Q", "A", {})
    assert res.verdict == ValidationVerdict.REJECTED
    assert res.reason == "rule failed"
    judge_val.validate.assert_not_called()

@pytest.mark.asyncio
async def test_composite_validator_layer1_passed_layer2_approved():
    import os
    os.environ["ENABLE_JUDGE_VALIDATION"] = "true"
    from unittest.mock import AsyncMock
    rule_val = MagicMock()
    rule_val.validate = AsyncMock(return_value=ValidationResult(ValidationVerdict.APPROVED, "rules ok", 1.0))
    
    judge_val = MagicMock()
    judge_val.validate = AsyncMock(return_value=ValidationResult(ValidationVerdict.APPROVED, "judge ok", 0.99))
    
    comp = CompositeValidator(rule_val, judge_val)
    res = await comp.validate("Q", "A", {})
    assert res.verdict == ValidationVerdict.APPROVED
    assert res.reason == "judge ok"
    judge_val.validate.assert_called_once()

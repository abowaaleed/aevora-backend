import pytest
from unittest.mock import MagicMock
from app.runtime.stages.generate_response import GenerateResponseStage
from app.runtime.stages.trivial_check import is_trivial_input
from app.runtime.types import PipelineContext, RuntimeRequest
from app.adaptive.types import AdaptiveDecision, IntentType, ResponseStyle, ThinkingMode
from app.services.ai_engine import AIEngine
from app.providers.base_provider import BaseProvider


class MockProvider(BaseProvider):
    def __init__(self):
        self.last_eval_count = 0
        self.generate_calls = []

    def generate(self, prompt: str, **kwargs) -> str:
        self.generate_calls.append((prompt, kwargs))
        return "Simulated AI response."


@pytest.fixture
def mock_ai_engine():
    provider = MockProvider()
    return AIEngine(provider=provider)


def test_is_trivial_input_exclusions():
    # Greetings are trivial
    assert is_trivial_input("مرحبا") is True
    assert is_trivial_input("hello") is True
    # Planning, explaining, list, days requests are excluded
    assert is_trivial_input("خطة الرياض") is False
    assert is_trivial_input("أيام سفر") is False
    assert is_trivial_input("برنامج سياحي") is False
    assert is_trivial_input("اشرح لي") is False
    assert is_trivial_input("travel plan") is False
    assert is_trivial_input("5 days list") is False


def test_determine_token_budget(mock_ai_engine):
    stage = GenerateResponseStage(mock_ai_engine)
    
    # 1. Greeting
    decision_greet = AdaptiveDecision(
        intent=IntentType.CONVERSATION,
        thinking_mode=ThinkingMode.FAST,
        response_style=ResponseStyle.ULTRA_SHORT,
        complexity_score=0.1,
        confidence=0.9
    )
    budget, task = stage._determine_token_budget("مرحبا", decision_greet)
    assert budget == 60
    assert task == "greeting_or_yes_no"

    # 2. Travel plan / programming
    decision_travel = AdaptiveDecision(
        intent=IntentType.TRAVEL,
        thinking_mode=ThinkingMode.NORMAL,
        response_style=ResponseStyle.LONG,
        complexity_score=0.7,
        confidence=0.9
    )
    budget, task = stage._determine_token_budget("برنامج سياحي لمكة", decision_travel)
    assert budget == 800
    assert task == "story_article_plan_or_programming"

    # 3. Learning/Explanation
    decision_learning = AdaptiveDecision(
        intent=IntentType.LEARNING,
        thinking_mode=ThinkingMode.NORMAL,
        response_style=ResponseStyle.MEDIUM,
        complexity_score=0.6,
        confidence=0.9
    )
    budget, task = stage._determine_token_budget("اشرح قاعدة المضارع البسيط", decision_learning)
    assert budget == 400
    assert task == "explanation_or_teaching"

    # 4. Explicit long answer
    budget, task = stage._determine_token_budget("اكتب خطة مفصلة للرياض", decision_travel)
    assert budget == 1200
    assert task == "explicit_long_answer"


def test_incomplete_response_detection(mock_ai_engine):
    stage = GenerateResponseStage(mock_ai_engine)
    
    # Natural endings
    assert stage._is_incomplete_response("الرياض مدينة جميلة.") is False
    assert stage._is_incomplete_response("Thanks for your help!") is False
    
    # Forbidden endings
    assert stage._is_incomplete_response("الرياض مدينة جميلة...") is True
    assert stage._is_incomplete_response("الرياض -") is True
    assert stage._is_incomplete_response("الرياض مدينة جميلة،") is True
    assert stage._is_incomplete_response("الرياض مدينة بل") is True
    
    # Repeated tatweel
    assert stage._is_incomplete_response("الرياض مدينة جميلةــــــــ") is True
    assert stage._is_incomplete_response("الرياضـ") is True
    
    # Trailing single conjunction
    assert stage._is_incomplete_response("الرياض مدينة جميلة و") is True


def test_generation_retry_on_incomplete(mock_ai_engine):
    stage = GenerateResponseStage(mock_ai_engine)
    
    # Setup context
    request = RuntimeRequest(
        user_message="اكتب خطة مفصلة للرياض",
        skill="quick"
    )
    context = PipelineContext(request=request)
    context.built_prompt = "Prompt context"
    context.adaptive_decision = AdaptiveDecision(
        intent=IntentType.TRAVEL,
        thinking_mode=ThinkingMode.NORMAL,
        response_style=ResponseStyle.LONG,
        complexity_score=0.7,
        confidence=0.9
    )
    
    # Mocking provider generate to return incomplete output on first call
    # and complete output on second call
    call_count = 0
    def mock_generate_fn(prompt, **kwargs):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            mock_ai_engine.provider.last_eval_count = 800
            return "هذه خطة السفر السياحية..."
        else:
            mock_ai_engine.provider.last_eval_count = 1100
            return "هذه خطة السفر السياحية كاملة لزيارة الرياض."
            
    mock_ai_engine.provider.generate = mock_generate_fn
    
    result = stage.execute(context)
    assert result.output == "هذه خطة السفر السياحية كاملة لزيارة الرياض."
    assert call_count == 2
    assert mock_ai_engine.provider.last_eval_count == 1100

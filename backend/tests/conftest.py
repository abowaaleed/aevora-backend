"""
Shared fixtures and configuration for pytest tests.
"""

import pytest
from unittest.mock import Mock, MagicMock
from app.adaptive import AdaptiveEngine
from app.skills.english import EnglishEngine
from app.prompt_engine import PromptLoader, SystemPrompt, SkillPrompt, PromptBuilder
from app.runtime import StageRegistry, Pipeline, Runtime, ContextManager
from app.runtime.types import RuntimeRequest, PipelineContext


@pytest.fixture
def adaptive_engine():
    """Provide AdaptiveEngine instance."""
    return AdaptiveEngine()


@pytest.fixture
def english_engine():
    """Provide EnglishEngine instance."""
    return EnglishEngine()


@pytest.fixture
def prompt_loader():
    """Provide PromptLoader instance."""
    return PromptLoader()


@pytest.fixture
def system_prompt(prompt_loader):
    """Provide SystemPrompt instance."""
    return SystemPrompt(loader=prompt_loader)


@pytest.fixture
def skill_prompt(prompt_loader):
    """Provide SkillPrompt instance."""
    return SkillPrompt(loader=prompt_loader)


@pytest.fixture
def prompt_builder(system_prompt, skill_prompt):
    """Provide PromptBuilder instance."""
    return PromptBuilder(system_prompt=system_prompt, skill_prompt=skill_prompt)


@pytest.fixture
def stage_registry(prompt_builder):
    """Provide StageRegistry with basic stages."""
    from app.runtime.stages import SkillDetectionStage, ReturnResponseStage
    from app.adaptive import AdaptiveEngine
    from app.runtime.stages import AdaptiveAnalysisStage
    
    registry = StageRegistry()
    adaptive_engine = AdaptiveEngine()
    registry.register(AdaptiveAnalysisStage(adaptive_engine=adaptive_engine))
    registry.register(SkillDetectionStage())
    registry.register(ReturnResponseStage())
    return registry


@pytest.fixture
def pipeline(stage_registry):
    """Provide Pipeline instance."""
    return Pipeline(
        registry=stage_registry,
        stage_order=["adaptive_analysis", "skill_detection", "return_response"]
    )


@pytest.fixture
def runtime(stage_registry, pipeline):
    """Provide Runtime instance."""
    return Runtime(registry=stage_registry, pipeline=pipeline)


@pytest.fixture
def runtime_request():
    """Provide RuntimeRequest instance."""
    return RuntimeRequest(
        user_message="Hello, how are you?",
        skill="quick",
        session_id="test_session"
    )


@pytest.fixture
def pipeline_context(runtime_request):
    """Provide PipelineContext instance."""
    return ContextManager.create_context(runtime_request)


@pytest.fixture
def mock_provider():
    """Provide mocked OllamaProvider."""
    provider = Mock()
    provider.generate = Mock(return_value="Test response")
    return provider


@pytest.fixture
def mock_ai_engine(mock_provider):
    """Provide mocked AIEngine."""
    from app.services.ai_engine import AIEngine
    engine = AIEngine(provider=mock_provider)
    return engine

import pytest
from app.runtime.stages.load_plugins import LoadPluginsStage
from app.runtime.types import PipelineContext, RuntimeRequest, StageStatus
from app.adaptive.types import AdaptiveDecision, IntentType, ThinkingMode, ResponseStyle


class TestLoadPluginsStage:
    """Test cases for LoadPluginsStage execution."""

    def test_load_plugins_stage_not_needed(self):
        stage = LoadPluginsStage()
        request = RuntimeRequest(user_message="Hello", skill="quick")
        context = PipelineContext(
            request=request,
            skill="quick",
            adaptive_decision=AdaptiveDecision(
                intent=IntentType.CONVERSATION,
                thinking_mode=ThinkingMode.FAST,
                response_style=ResponseStyle.SHORT,
                need_memory=False,
                need_plugins=False,  # Plugins not needed!
                complexity_score=0.1,
                confidence=0.9
            )
        )
        
        result = stage.execute(context)
        assert result.status == StageStatus.SKIPPED
        assert context.plugins is None
        assert context.plugins_data is None

    def test_load_plugins_stage_calculation(self):
        stage = LoadPluginsStage()
        request = RuntimeRequest(user_message="calculate 2 + 5", skill="quick")
        context = PipelineContext(
            request=request,
            skill="quick",
            adaptive_decision=AdaptiveDecision(
                intent=IntentType.LEARNING,
                thinking_mode=ThinkingMode.FAST,
                response_style=ResponseStyle.SHORT,
                need_memory=False,
                need_plugins=True,  # Plugins needed!
                complexity_score=0.3,
                confidence=0.9
            )
        )
        
        result = stage.execute(context)
        assert result.status == StageStatus.COMPLETED
        assert context.plugins == "calculator"
        assert "7" in context.plugins_data

    def test_load_plugins_stage_no_match(self):
        stage = LoadPluginsStage()
        request = RuntimeRequest(user_message="no matching plugin keywords here", skill="quick")
        context = PipelineContext(
            request=request,
            skill="quick",
            adaptive_decision=AdaptiveDecision(
                intent=IntentType.LEARNING,
                thinking_mode=ThinkingMode.FAST,
                response_style=ResponseStyle.SHORT,
                need_memory=False,
                need_plugins=True,  # Plugins needed!
                complexity_score=0.3,
                confidence=0.9
            )
        )
        
        result = stage.execute(context)
        assert result.status == StageStatus.SKIPPED
        assert context.plugins is None
        assert context.plugins_data is None

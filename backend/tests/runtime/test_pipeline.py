"""
Unit tests for Runtime Pipeline.
"""

import pytest
from app.runtime import StageRegistry, Pipeline, Runtime, ContextManager
from app.runtime.types import RuntimeRequest, StageStatus
from app.runtime.stages import SkillDetectionStage, ReturnResponseStage, AdaptiveAnalysisStage
from app.adaptive import AdaptiveEngine


class TestStageRegistry:
    """Test cases for StageRegistry."""
    
    def test_register_stage(self):
        """Test registering a stage."""
        registry = StageRegistry()
        stage = SkillDetectionStage()
        
        registry.register(stage)
        
        assert registry.has("skill_detection")
        assert registry.count() == 1
    
    def test_register_duplicate_stage(self):
        """Test that duplicate stage names are not allowed."""
        registry = StageRegistry()
        stage1 = SkillDetectionStage()
        stage2 = SkillDetectionStage()
        
        registry.register(stage1)
        
        with pytest.raises(ValueError):
            registry.register(stage2)
    
    def test_get_stage(self):
        """Test getting a registered stage."""
        registry = StageRegistry()
        stage = SkillDetectionStage()
        
        registry.register(stage)
        retrieved = registry.get("skill_detection")
        
        assert retrieved is stage
    
    def test_get_nonexistent_stage(self):
        """Test getting a non-existent stage."""
        registry = StageRegistry()
        
        with pytest.raises(ValueError):
            registry.get("nonexistent")
    
    def test_get_all_stages(self):
        """Test getting all registered stages."""
        registry = StageRegistry()
        stage1 = SkillDetectionStage()
        stage2 = ReturnResponseStage()
        
        registry.register(stage1)
        registry.register(stage2)
        
        all_stages = registry.get_all()
        
        assert len(all_stages) == 2
        assert "skill_detection" in all_stages
        assert "return_response" in all_stages
    
    def test_unregister_stage(self):
        """Test unregistering a stage."""
        registry = StageRegistry()
        stage = SkillDetectionStage()
        
        registry.register(stage)
        registry.unregister("skill_detection")
        
        assert not registry.has("skill_detection")
        assert registry.count() == 0
    
    def test_clear_all_stages(self):
        """Test clearing all stages."""
        registry = StageRegistry()
        registry.register(SkillDetectionStage())
        registry.register(ReturnResponseStage())
        
        registry.clear()
        
        assert registry.count() == 0


class TestPipeline:
    """Test cases for Pipeline."""
    
    def test_pipeline_execution(self, stage_registry):
        """Test executing a pipeline."""
        pipeline = Pipeline(
            registry=stage_registry,
            stage_order=["adaptive_analysis", "skill_detection", "return_response"]
        )
        
        request = RuntimeRequest(
            user_message="Hello",
            skill="quick",
            session_id="test"
        )
        
        context = ContextManager.create_context(request)
        result_context = pipeline.execute(context)
        
        assert result_context is not None
        assert len(result_context.stage_results) == 3
    
    def test_pipeline_stage_order(self, stage_registry):
        """Test that stages execute in the correct order."""
        pipeline = Pipeline(
            registry=stage_registry,
            stage_order=["adaptive_analysis", "skill_detection", "return_response"]
        )
        
        request = RuntimeRequest(user_message="Hello", skill="quick")
        context = ContextManager.create_context(request)
        result_context = pipeline.execute(context)
        
        stage_names = [r.stage_name for r in result_context.stage_results]
        assert stage_names == ["adaptive_analysis", "skill_detection", "return_response"]
    
    def test_pipeline_with_missing_stage(self, stage_registry):
        """Test pipeline with a missing stage in order."""
        pipeline = Pipeline(
            registry=stage_registry,
            stage_order=["adaptive_analysis", "nonexistent", "skill_detection"]
        )
        
        request = RuntimeRequest(user_message="Hello", skill="quick")
        context = ContextManager.create_context(request)
        
        with pytest.raises(ValueError):
            pipeline.execute(context)
    
    def test_get_stage_order(self, stage_registry):
        """Test getting stage order."""
        pipeline = Pipeline(
            registry=stage_registry,
            stage_order=["adaptive_analysis", "skill_detection"]
        )
        
        order = pipeline.get_stage_order()
        assert order == ["adaptive_analysis", "skill_detection"]
    
    def test_set_stage_order(self, stage_registry):
        """Test setting stage order."""
        pipeline = Pipeline(
            registry=stage_registry,
            stage_order=["adaptive_analysis", "skill_detection"]
        )
        
        new_order = ["skill_detection", "adaptive_analysis"]
        pipeline.set_stage_order(new_order)
        
        assert pipeline.get_stage_order() == new_order


class TestRuntime:
    """Test cases for Runtime."""
    
    def test_runtime_process(self, runtime):
        """Test runtime processing."""
        request = RuntimeRequest(
            user_message="Hello",
            skill="quick",
            session_id="test"
        )
        
        response = runtime.process(request)
        
        assert response is not None
        assert response.reply is not None
        assert response.skill_used == "quick"
        assert len(response.stages_executed) > 0

    def test_runtime_process_includes_runtime_metadata(self, runtime):
        """Test runtime processing includes structured metadata."""
        request = RuntimeRequest(
            user_message="Hello",
            skill="quick",
            session_id="test",
            mode="quick"
        )

        response = runtime.process(request)

        assert response.runtime is not None
        assert response.runtime.selected_mode == "quick"
        assert response.runtime.selected_skill == "quick"
        assert response.runtime.provider is not None
        assert response.runtime.response_duration_ms >= 0
    
    def test_runtime_with_different_skills(self, runtime):
        """Test runtime with different skills."""
        skills = ["quick", "english", "programmer"]
        
        for skill in skills:
            request = RuntimeRequest(
                user_message="Test message",
                skill=skill,
                session_id="test"
            )
            
            response = runtime.process(request)
            assert response.skill_used == skill
    
    def test_runtime_get_registry(self, runtime):
        """Test getting stage registry from runtime."""
        registry = runtime.get_registry()
        assert registry is not None
        assert isinstance(registry, StageRegistry)
    
    def test_runtime_get_pipeline(self, runtime):
        """Test getting pipeline from runtime."""
        pipeline = runtime.get_pipeline()
        assert pipeline is not None
        assert isinstance(pipeline, Pipeline)
    
    def test_runtime_get_registered_stages(self, runtime):
        """Test getting registered stage names."""
        stages = runtime.get_registered_stages()
        assert isinstance(stages, list)
        assert len(stages) > 0
        assert "skill_detection" in stages


class TestContextManager:
    """Test cases for ContextManager."""
    
    def test_create_context(self):
        """Test creating a context from request."""
        request = RuntimeRequest(
            user_message="Hello",
            skill="quick",
            session_id="test"
        )
        
        context = ContextManager.create_context(request)
        
        assert context.request == request
        assert context.skill == "quick"
        assert context.stage_results == []
    
    def test_validate_context(self, pipeline_context):
        """Test context validation."""
        is_valid = ContextManager.validate_context(pipeline_context)
        assert is_valid is True
    
    def test_get_skill(self, pipeline_context):
        """Test getting skill from context."""
        skill = ContextManager.get_skill(pipeline_context)
        assert skill == "quick"
    
    def test_set_skill(self, pipeline_context):
        """Test setting skill in context."""
        ContextManager.set_skill(pipeline_context, "english")
        assert ContextManager.get_skill(pipeline_context) == "english"
    
    def test_get_stage_result(self, pipeline_context):
        """Test getting stage result from context."""
        from app.runtime.types import StageResult, StageStatus
        
        result = StageResult(
            stage_name="test_stage",
            status=StageStatus.COMPLETED,
            output="test output"
        )
        pipeline_context.stage_results.append(result)
        
        retrieved = ContextManager.get_stage_result(pipeline_context, "test_stage")
        assert retrieved is result
    
    def test_did_stage_succeed(self, pipeline_context):
        """Test checking if a stage succeeded."""
        from app.runtime.types import StageResult, StageStatus
        
        result = StageResult(
            stage_name="test_stage",
            status=StageStatus.COMPLETED,
            output="test output"
        )
        pipeline_context.stage_results.append(result)
        
        succeeded = ContextManager.did_stage_succeed(pipeline_context, "test_stage")
        assert succeeded is True

    def test_save_memory_stage_skipped(self):
        """Test SaveMemoryStage skipping when no trigger present."""
        from app.runtime.stages.save_memory import SaveMemoryStage
        from app.runtime.types import PipelineContext, RuntimeRequest
        
        stage = SaveMemoryStage()
        context = PipelineContext(
            request=RuntimeRequest(user_message="Hello how are you?")
        )
        res = stage.execute(context)
        assert "skipped" in res.status.value.lower()

    def test_save_memory_stage_saves(self):
        """Test SaveMemoryStage extraction and saving memory."""
        from app.runtime.stages.save_memory import SaveMemoryStage
        from app.runtime.types import PipelineContext, RuntimeRequest
        
        stage = SaveMemoryStage()
        context = PipelineContext(
            request=RuntimeRequest(user_message="Remember that my favorite food is pizza")
        )
        res = stage.execute(context)
        assert "completed" in res.status.value.lower()
        
        # Verify it was added to memory
        from main import get_memory_service
        mems = get_memory_service().get_memories("default")
        assert any("pizza" in m.content for m in mems)

    def test_save_memory_stage_saves_arabic_facts(self):
        """Test SaveMemoryStage automatic Arabic facts extraction."""
        from app.runtime.stages.save_memory import SaveMemoryStage
        from app.runtime.types import PipelineContext, RuntimeRequest
        from main import get_memory_service
        
        stage = SaveMemoryStage()
        
        # Test Name
        context = PipelineContext(request=RuntimeRequest(user_message="اسمي صالح"))
        res = stage.execute(context)
        assert res.status.value == "completed"
        
        # Test Club
        context = PipelineContext(request=RuntimeRequest(user_message="أحب نادي الهلال"))
        res = stage.execute(context)
        assert res.status.value == "completed"

        # Test City
        context = PipelineContext(request=RuntimeRequest(user_message="أعيش في بريدة"))
        res = stage.execute(context)
        assert res.status.value == "completed"

        # Test App Name
        context = PipelineContext(request=RuntimeRequest(user_message="اسم التطبيق أيفورا"))
        res = stage.execute(context)
        assert res.status.value == "completed"

        # Verify all are stored
        mems = get_memory_service().get_memories("default")
        m_contents = [m.content for m in mems]
        assert any("الاسم: صالح" in c for c in m_contents)
        assert any("النادي المفضل: الهلال" in c for c in m_contents)
        assert any("المدينة: بريدة" in c for c in m_contents)
        assert any("اسم التطبيق: أيفورا" in c for c in m_contents)

    def test_build_prompt_stage_executes(self):
        """Test BuildPromptStage executes and builds prompt with history."""
        from app.runtime.stages.build_prompt import BuildPromptStage, save_history
        from app.runtime.types import PipelineContext, RuntimeRequest
        from app.prompt_engine import PromptBuilder, SystemPrompt, SkillPrompt, PromptLoader
        
        loader = PromptLoader()
        builder = PromptBuilder(SystemPrompt(loader), SkillPrompt(loader))
        stage = BuildPromptStage(builder)
        
        # Save mock history
        save_history("test_user_bp", [{"role": "user", "content": "Hi"}, {"role": "assistant", "content": "Hello"}])
        
        context = PipelineContext(
            request=RuntimeRequest(user_message="Tell me a joke", user_id="test_user_bp")
        )
        res = stage.execute(context)
        assert res.status.value == "completed"
        assert "Aevora: Hello" in context.built_prompt

import sys
import os
import time
from pathlib import Path

# Add project root to path
sys.path.append(str(Path(__file__).parent.parent))

from app.providers.ollama_provider import OllamaProvider
from app.services.ai_engine import AIEngine
from app.adaptive import AdaptiveEngine
from app.skills.english import EnglishEngine
from app.memory import MemoryService
from app.user_brain import UserBrainService
from app.prompt_engine import PromptBuilder, Skill
from app.runtime.registry import StageRegistry
from app.runtime.pipeline import Pipeline
from app.runtime.types import RuntimeRequest, PipelineContext
from app.runtime.context import ContextManager
from app.runtime.stages.adaptive_analysis import AdaptiveAnalysisStage
from app.runtime.stages.english_processing import EnglishProcessingStage
from app.runtime.stages.entity_extraction import EntityExtractionStage
from app.runtime.stages.topic_classification import TopicClassificationStage
from app.runtime.stages.reasoning import ReasoningStage
from app.runtime.stages.load_memory import LoadMemoryStage
from app.runtime.stages.knowledge_verification import KnowledgeVerificationStage
from app.runtime.stages.build_prompt import BuildPromptStage
from app.runtime.stages.generate_response import GenerateResponseStage
from app.runtime.stages.consistency_checker import ConsistencyCheckerStage
from app.runtime.stages.validator import ResponseValidationStage
from app.runtime.stages.save_memory import SaveMemoryStage
from app.runtime.stages.return_response import ReturnResponseStage

def run_diagnostics():
    provider = OllamaProvider()
    ai_engine = AIEngine(provider=provider)
    adaptive_engine = AdaptiveEngine()
    english_engine = EnglishEngine()
    memory_service = MemoryService()
    from app.prompt_engine import PromptLoader, SystemPrompt, SkillPrompt
    loader = PromptLoader()
    system_prompt = SystemPrompt(loader=loader)
    skill_prompt = SkillPrompt(loader=loader)
    prompt_builder = PromptBuilder(system_prompt=system_prompt, skill_prompt=skill_prompt)

    # Track individual sub-components inside validation
    validation_timings = {}
    
    # We will patch AIEngine generate calls to count LLM invocations and measure their durations
    original_generate = provider.generate
    llm_calls = []
    
    def tracked_generate(prompt, **kwargs):
        start = time.perf_counter()
        # Find which prompt it is
        if "Logical & Factual Verification" in prompt:
            call_type = "Self-Critique"
        elif "Independent Judge" in prompt:
            call_type = "Judge Validator"
        elif "REFINEMENT REQUIRED" in prompt:
            call_type = "Refinement/Regeneration"
        elif "Entity Extraction" in prompt or "Extraction" in prompt:
            call_type = "Entity Extraction"
        elif "Classification" in prompt:
            call_type = "Topic Classification"
        elif "Consistency" in prompt or "Checker" in prompt:
            call_type = "Consistency Checker"
        else:
            call_type = "Initial Response Generation"
            
        res = original_generate(prompt, **kwargs)
        dur = (time.perf_counter() - start) * 1000.0
        llm_calls.append((call_type, dur, len(prompt), len(res)))
        return res
        
    provider.generate = tracked_generate

    # Setup stages
    registry = StageRegistry()
    registry.register(AdaptiveAnalysisStage(adaptive_engine=adaptive_engine))
    registry.register(EnglishProcessingStage(english_engine=english_engine))
    registry.register(EntityExtractionStage(ai_engine=ai_engine))
    registry.register(TopicClassificationStage(ai_engine=ai_engine))
    registry.register(ReasoningStage(memory_service=memory_service))
    registry.register(LoadMemoryStage(service=memory_service))
    registry.register(KnowledgeVerificationStage(ai_engine=ai_engine))
    registry.register(BuildPromptStage(prompt_builder=prompt_builder))
    registry.register(GenerateResponseStage(ai_engine=ai_engine))
    registry.register(ConsistencyCheckerStage(ai_engine=ai_engine))
    registry.register(ResponseValidationStage(ai_engine=ai_engine))
    registry.register(SaveMemoryStage(ai_engine=ai_engine))
    registry.register(ReturnResponseStage())

    stage_order = [
        "adaptive_analysis",
        "english_processing",
        "entity_extraction",
        "topic_classification",
        "reasoning",
        "load_memory",
        "knowledge_verification",
        "build_prompt",
        "generate_response",
        "consistency_checker",
        "response_validation",
        "save_memory",
        "return_response"
    ]

    pipeline = Pipeline(registry=registry, stage_order=stage_order)
    
    cases = [
        ("Case 1 (Low - Greeting)", "مرحبا", "quick"),
        ("Case 2 (Medium - Weather)", "what is the weather like", "quick"),
        ("Case 3 (High - Factual)", "why doesn't a male lion give birth", "quick"),
    ]

    for title, query, skill in cases:
        print("\n" + "="*80)
        print(f"RUNNING: {title} - Query: '{query}'")
        print("="*80)
        
        # Clear LLM call logs to track each case independently
        llm_calls.clear()
        
        request = RuntimeRequest(
            user_message=query,
            skill=skill,
            session_id=f"session_{title.replace(' ', '_')}",
            user_id="diagnostic_user"
        )
        context = ContextManager.create_context(request)

        # Manually run adaptive analysis first to see the tier
        decision = adaptive_engine.analyze(query)
        print(f"TIER: {decision.tier} (Complexity: {decision.complexity_score:.2f})")

        pipeline.execute(context)
        
        print("\nSTAGE TIMINGS:")
        total_time = 0
        for r in context.stage_results:
            print(f"  {r.stage_name:<25} : {r.duration_ms:>10.2f} ms ({r.status.value})")
            total_time += r.duration_ms
        print(f"  Total Pipeline Time       : {total_time:>10.2f} ms ({total_time/1000.0:.2f} seconds)")
        
        print("\nLLM CALLS:")
        for call_type, dur, p_len, r_len in llm_calls:
            print(f"  {call_type:<30} | {dur:>13.2f} ms | {p_len:>5} -> {r_len:>4}")
        
        print("\nRESPONSE PREVIEW:")
        preview = context.ai_response or ""
        # print first 2 lines
        lines = preview.split("\n")
        for line in lines[:5]:
            print(f"  {line}")
        if len(lines) > 5:
            print("  ...")
        print("="*80)

if __name__ == "__main__":
    run_diagnostics()

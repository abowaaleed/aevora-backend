"""
Runtime Engine — Simplified for Mustafeed.

Strips memory, adaptive decision, personality, and plugins references.
"""

import time

from .types import RuntimeRequest, RuntimeResponse, RuntimeMetadata, PromptStatistics, ProviderInfo, StageTiming
from .context import ContextManager
from .registry import StageRegistry
from .pipeline import Pipeline


class Runtime:
    """Main orchestrator for Mustafeed pipeline."""

    def __init__(self, registry: StageRegistry, pipeline: Pipeline):
        self.registry = registry
        self.pipeline = pipeline

    def process(self, request: RuntimeRequest) -> RuntimeResponse:
        start_time = time.perf_counter()

        context = ContextManager.create_context(request)

        if not ContextManager.validate_context(context):
            return RuntimeResponse(
                reply="Invalid request: missing required fields",
                skill_used="error",
                stages_executed=[],
                runtime=None,
            )

        context = self.pipeline.execute(context)

        skill_used = ContextManager.get_skill(context)
        ai_response = context.direct_response or context.ai_response or "No response generated"
        stages_executed = [result.stage_name for result in context.stage_results]

        stage_timings = [
            StageTiming(
                name=result.stage_name,
                status=result.status.value if hasattr(result.status, "value") else str(result.status),
                duration_ms=int(result.duration_ms) if result.duration_ms is not None else 0,
                details=result.error or None,
            )
            for result in context.stage_results
        ]

        prompt_statistics = None
        if context.built_prompt:
            prompt_statistics = PromptStatistics(
                prompt_length=len(context.built_prompt),
                user_message_length=len(context.request.user_message),
            )

        provider_info = None
        if context.provider_info:
            provider_info = ProviderInfo(
                name=context.provider_info.name,
                model=context.provider_info.model,
                endpoint=context.provider_info.endpoint,
            )
        if provider_info is None:
            provider_info = ProviderInfo(name="local", model="unknown")

        metadata = RuntimeMetadata(
            selected_skill=skill_used,
            provider=provider_info,
            prompt_statistics=prompt_statistics,
            stage_timings=stage_timings,
            response_duration_ms=max(0, int((time.perf_counter() - start_time) * 1000)),
        )

        return RuntimeResponse(
            reply=ai_response,
            skill_used=skill_used,
            stages_executed=stages_executed,
            runtime=metadata,
        )

    def get_registry(self) -> StageRegistry:
        return self.registry

    def get_pipeline(self) -> Pipeline:
        return self.pipeline

    def get_registered_stages(self) -> list[str]:
        return self.registry.get_names()

    def get_stage_order(self) -> list[str]:
        return self.pipeline.get_stage_order()

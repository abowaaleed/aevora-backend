"""
Pipeline execution — Simplified for Mustafeed.

Stripped of trace logging that references removed context fields.
"""

from typing import List
from .types import PipelineContext, StageResult, StageStatus
from .task import Stage
from .registry import StageRegistry


class Pipeline:
    """Pipeline executor for sequential stage execution."""

    def __init__(self, registry: StageRegistry, stage_order: List[str]):
        self.registry = registry
        self.stage_order = stage_order

    def execute(self, context: PipelineContext) -> PipelineContext:
        for stage_name in self.stage_order:
            if not self.registry.has(stage_name):
                result = StageResult(
                    stage_name=stage_name,
                    status=StageStatus.FAILED,
                    error=f"Stage '{stage_name}' not found in registry"
                )
                context.stage_results.append(result)
                raise ValueError(f"Stage '{stage_name}' is not registered")

            stage = self.registry.get(stage_name)
            result = stage.execute_with_timing(context)
            context.stage_results.append(result)

            if result.status == StageStatus.FAILED:
                break

            # Short-circuit: if RAG set direct_response, skip remaining stages
            if context.direct_response is not None:
                break

        # Minimal trace logging
        try:
            total_time_ms = sum(r.duration_ms for r in context.stage_results if r.duration_ms)
            print(f"\n[MUSTAFEED] Pipeline completed in {total_time_ms:.0f}ms")
            for r in context.stage_results:
                duration = f"{r.duration_ms:.0f}ms" if r.duration_ms is not None else "N/A"
                print(f"  [{r.stage_name}] {r.status} ({duration})")
            print(f"  Response: {(context.ai_response or context.direct_response or 'N/A')[:100]}...")
        except Exception as e:
            print(f"Error logging pipeline: {e}")

        return context

    def execute_stage(self, stage_name: str, context: PipelineContext) -> PipelineContext:
        if not self.registry.has(stage_name):
            raise ValueError(f"Stage '{stage_name}' is not registered")

        stage = self.registry.get(stage_name)
        result = stage.execute_with_timing(context)
        context.stage_results.append(result)
        return context

    def get_stage_order(self) -> List[str]:
        return self.stage_order.copy()

    def set_stage_order(self, stage_order: List[str]) -> None:
        for stage_name in stage_order:
            if not self.registry.has(stage_name):
                raise ValueError(f"Stage '{stage_name}' is not registered")
        self.stage_order = stage_order

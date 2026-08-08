"""
Generate Response Stage — Simplified for Mustafeed.

Single LLM call only. No regeneration logic, no English skill parsing,
no session summary, no incomplete response detection.
"""

import re
from ..task import Stage
from ..types import PipelineContext, StageStatus, ProviderInfo
from app.services.ai_engine import AIEngine


class GenerateResponseStage(Stage):
    """
    Simplified generation stage — one LLM call, no retries.
    """

    def __init__(self, ai_engine: AIEngine):
        super().__init__("generate_response")
        self.ai_engine = ai_engine

    def execute(self, context: PipelineContext):
        # If response was already set (e.g. structured answer), skip
        if context.ai_response is not None:
            return self._create_result(
                status=StageStatus.SKIPPED,
                output="Response already set"
            )

        prompt = context.built_prompt
        if prompt is None:
            return self._create_result(
                status=StageStatus.FAILED,
                error="No prompt built"
            )

        # Single LLM call with fixed budget
        response = self.ai_engine.generate_with_prompt(prompt, num_predict=400)

        # Clean tatweel
        response = re.sub(r'ـ+$', '', response).strip()
        response = re.sub(r'ـ+ ', ' ', response).strip()

        # Strip any leaked tags
        response = re.sub(r'\[SYSTEM:.*?\]', '', response).strip()

        # Provider info
        provider_name = getattr(getattr(self.ai_engine, "provider", None), "__class__", type(None)).__name__
        provider_model = getattr(getattr(self.ai_engine, "provider", None), "model", None)
        context.provider_info = ProviderInfo(
            name=provider_name.replace("Provider", "").lower() or "provider",
            model=provider_model,
            endpoint=getattr(getattr(self.ai_engine, "provider", None), "api_url", None),
        )

        context.ai_response = response

        return self._create_result(
            status=StageStatus.COMPLETED,
            output=response
        )

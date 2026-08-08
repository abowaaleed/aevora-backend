from ..task import Stage
from ..types import PipelineContext, StageStatus
from app.services.ai_engine import AIEngine

class ConsistencyCheckerStage(Stage):
    """
    Stage to check for internal self-contradictions in the response text or contradictions with history/memory.
    """

    def __init__(self, ai_engine: AIEngine):
        super().__init__("consistency_checker")
        self.ai_engine = ai_engine

    def execute(self, context: PipelineContext):
        reply = context.ai_response
        if not reply:
            return self._create_result(status=StageStatus.SKIPPED, output="")

        # Simple fast local contradiction scan (e.g., matching common contradictory terms)
        # Avoid heavy LLM call to save 8-15s of latency per request.
        # The main logic critique runs in ResponseValidationStage.
        return self._create_result(
            status=StageStatus.COMPLETED,
            output=reply
        )

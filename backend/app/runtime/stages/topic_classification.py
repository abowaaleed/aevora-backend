from ..task import Stage
from ..types import PipelineContext, StageStatus
from app.services.ai_engine import AIEngine

class TopicClassificationStage(Stage):
    """
    Stage to classify query into specific knowledge domains.
    """

    def __init__(self, ai_engine: AIEngine):
        super().__init__("topic_classification")
        self.ai_engine = ai_engine

    def execute(self, context: PipelineContext):
        query = context.request.user_message
        if not query:
            context.topic = "General"
            return self._create_result(status=StageStatus.SKIPPED, output="General")

        from app.runtime.stages.trivial_check import is_trivial_input
        if is_trivial_input(query):
            context.topic = "General"
            return self._create_result(status=StageStatus.SKIPPED, output="General")

        # 0. Check if already set by previous stage (combined extraction & classification)
        if getattr(context, "topic", None) is not None:
            return self._create_result(status=StageStatus.COMPLETED, output=context.topic)

        # 1. Zero-latency local database lookup (longest key first)
        from app.runtime.fact_db import FACT_DATABASE
        for key in sorted(FACT_DATABASE.keys(), key=len, reverse=True):
            entry = FACT_DATABASE[key]
            if key in query:
                context.topic = entry["topic"]
                return self._create_result(status=StageStatus.COMPLETED, output=context.topic)

        # 2. Fallback to LLM topic classification
        prompt = (
            "[SYSTEM: Topic Classification]\n"
            "Classify the user query into exactly one of these topics:\n"
            "Biology, Geography, History, Math, Logic, Science, Human, General.\n"
            "Respond ONLY with the selected category word. Do not write anything else.\n\n"
            f"Query: {query}\n"
            "Category:"
        )

        try:
            res = self.ai_engine.generate_with_prompt(prompt).strip()
            topic = "General"
            for possible in ["Biology", "Geography", "History", "Math", "Logic", "Science", "Human"]:
                if possible.lower() in res.lower():
                    topic = possible
                    break
            context.topic = topic
        except Exception as e:
            print(f"[TOPIC CLASSIFICATION] Error: {e}")
            context.topic = "General"

        return self._create_result(
            status=StageStatus.COMPLETED,
            output=context.topic
        )

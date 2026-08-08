from ..task import Stage
from ..types import PipelineContext, StageStatus
from app.services.ai_engine import AIEngine

class EntityExtractionStage(Stage):
    """
    Stage to extract primary entities/nouns from the user message.
    """

    def __init__(self, ai_engine: AIEngine):
        super().__init__("entity_extraction")
        self.ai_engine = ai_engine

    def execute(self, context: PipelineContext):
        query = context.request.user_message
        if not query:
            context.entities = []
            return self._create_result(status=StageStatus.SKIPPED, output=[])

        if context.adaptive_decision and context.adaptive_decision.tier == "low":
            print("[ENTITY EXTRACTION] Low complexity tier detected. Skipping stage.")
            context.entities = []
            return self._create_result(status=StageStatus.SKIPPED, output="Skipped due to low complexity")

        from app.runtime.stages.trivial_check import is_trivial_input
        if is_trivial_input(query):
            context.entities = []
            return self._create_result(status=StageStatus.SKIPPED, output="Trivial input skipped")

        # 1. Zero-latency local database lookup (longest key first)
        from app.runtime.fact_db import FACT_DATABASE
        matched = []
        for key in sorted(FACT_DATABASE.keys(), key=len, reverse=True):
            entry = FACT_DATABASE[key]
            if key in query:
                matched.extend(entry["entities"])
                break  # Stop at the most specific match
        if matched:
            context.entities = list(set(matched))
            return self._create_result(status=StageStatus.COMPLETED, output=context.entities)

        # 2. Fallback to combined LLM extraction & topic classification
        prompt = (
            "[SYSTEM: Extraction & Classification]\n"
            "Analyze the user query. Extract primary entities and classify the topic.\n"
            "Topics: Biology, Geography, History, Math, Logic, Science, Human, General.\n"
            "Respond ONLY with JSON format:\n"
            "{\n"
            '  "entities": ["...", "..."],\n'
            '  "topic": "..."\n'
            "}\n\n"
            f"Query: {query}"
        )

        try:
            import json
            import re
            res = self.ai_engine.generate_with_prompt(prompt).strip()
            match = re.search(r"\{.*\}", res, re.DOTALL)
            if match:
                data = json.loads(match.group(0))
                entities = data.get("entities", [])
                topic = data.get("topic", "General")
                
                # Clean entities
                entities = [e.strip() for e in entities if e.strip() and len(e.strip()) < 25]
                context.entities = [e.replace("-", "").replace("*", "").strip() for e in entities]
                context.topic = topic
            else:
                raise ValueError("No JSON found in response")
        except Exception as e:
            print(f"[ENTITY EXTRACTION] Combined analysis error: {e}")
            context.entities = []
            context.topic = "General"

        return self._create_result(
            status=StageStatus.COMPLETED,
            output=context.entities
        )

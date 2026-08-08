from ..task import Stage
from ..types import PipelineContext, StageStatus
from app.services.ai_engine import AIEngine

class KnowledgeVerificationStage(Stage):
    """
    Stage to resolve core factual/scientific rules before prompt building.
    """

    def __init__(self, ai_engine: AIEngine):
        super().__init__("knowledge_verification")
        self.ai_engine = ai_engine

    def execute(self, context: PipelineContext):
        query = context.request.user_message
        if not query:
            return self._create_result(status=StageStatus.SKIPPED, output="")

        # If RAG stage already found relevant document knowledge, preserve it.
        if context.relevant_knowledge:
            print("[KNOWLEDGE VERIFICATION] relevant_knowledge already set by RAG. Skipping to preserve document context.")
            return self._create_result(status=StageStatus.SKIPPED, output="Skipped: RAG knowledge preserved")

        if context.adaptive_decision and context.adaptive_decision.tier == "low":
            print("[KNOWLEDGE VERIFICATION] Low complexity tier detected. Skipping stage.")
            return self._create_result(status=StageStatus.SKIPPED, output="Skipped due to low complexity")

        # 1. Zero-latency local database lookup (longest key first)
        from app.runtime.fact_db import FACT_DATABASE
        for key in sorted(FACT_DATABASE.keys(), key=len, reverse=True):
            entry = FACT_DATABASE[key]
            if key in query:
                context.relevant_knowledge = entry["knowledge"]
                return self._create_result(status=StageStatus.COMPLETED, output=context.relevant_knowledge)

        # 2. Only verify facts for categories that benefit from objective world facts
        if context.topic in ["General", "English"]:
            # Check if it has a reason question keyword, otherwise skip to save time
            reason_keywords = ["لماذا", "كيف", "كم", "هل", "why", "how", "what", "where"]
            if not any(k in query.lower() for k in reason_keywords):
                context.relevant_knowledge = ""
                return self._create_result(status=StageStatus.SKIPPED, output="")

        prompt = (
            "[SYSTEM: Scientific & Factual Reality Verification]\n"
            "Determine the absolute, verified biological/scientific/mathematical/geographical rule or factual reality regarding the entities and the user's question.\n"
            "Format: Output ONLY 1 short, highly accurate sentence in the query's language. Be direct, clear, and objective. "
            "Never assume, guess, or lie. If you don't know the exact rule, write 'UNKNOWN'.\n\n"
            f"Question: {query}\n"
            f"Entities: {', '.join(context.entities) if context.entities else 'None'}\n"
            f"Topic: {context.topic}\n\n"
            "Factual Rule:"
        )

        try:
            res = self.ai_engine.generate_with_prompt(prompt).strip()
            if "UNKNOWN" in res.upper() or len(res) < 3:
                context.relevant_knowledge = ""
            else:
                context.relevant_knowledge = res
        except Exception as e:
            print(f"[KNOWLEDGE VERIFICATION] Error: {e}")
            context.relevant_knowledge = ""

        return self._create_result(
            status=StageStatus.COMPLETED,
            output=context.relevant_knowledge
        )

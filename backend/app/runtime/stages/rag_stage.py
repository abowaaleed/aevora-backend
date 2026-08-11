from ..task import Stage
from ..types import PipelineContext, StageStatus
from app.rag.document_service import get_document_service
from app.core.user_context import current_user_id
import re

class RAGStage(Stage):
    """
    Stage to retrieve relevant content from private uploaded documents.
    Always runs — if no documents are indexed, the query returns quickly with no results.
    """

    def __init__(self):
        super().__init__("rag")

    def execute(self, context: PipelineContext):
        query = context.request.user_message
        if not query:
            return self._create_result(status=StageStatus.SKIPPED, output="")

        uid = context.request.user_id or current_user_id()
        doc_service = get_document_service(uid)

        # Always run RAG if documents exist — regardless of mode/skill.
        # Check vector store directly for indexed documents.
        try:
            check = doc_service.vector_store.collection.get(limit=1)
            has_docs = bool(check and check.get("documents") and len(check["documents"]) > 0)
        except Exception:
            has_docs = False
        if not has_docs:
            return self._create_result(status=StageStatus.SKIPPED, output="No documents indexed")

        print(f"[RAG STAGE] Executing query: {query}")
        rag_result = doc_service.query(query)

        # Only inject if we found something meaningful
        answer = rag_result.get("answer", "")
        rag_type = rag_result.get("type", "none")
        if rag_type == "none" or not answer:
            return self._create_result(status=StageStatus.SKIPPED, output="No relevant documents found")

        # Short-circuit for structured answers and aggregation refusals — bypass LLM
        if rag_type in ("structured_answer", "aggregation_refused"):
            print(f"[RAG STAGE] Short-circuit for {rag_type}")
            context.direct_response = answer
            return self._create_result(
                status=StageStatus.COMPLETED,
                output=rag_result
            )

        # Store in context for prompt builder
        context.relevant_knowledge = answer

        # Also store source info for citation
        source = rag_result.get("source") or rag_result.get("sources")
        if source:
            context.relevant_knowledge += f"\n[المصدر: {source}]"

        # Mark RAG as used in extensions
        print(f"[RAG STAGE] RAG type: {rag_type}, answer length: {len(answer)} chars")

        return self._create_result(
            status=StageStatus.COMPLETED,
            output=rag_result
        )

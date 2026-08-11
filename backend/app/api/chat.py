from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from app.models.chat import ChatRequest, ChatResponse
from app.services.conversation_manager import ConversationManager
from app.providers.gemini_provider import GeminiProvider
from app.services.smart_router import SmartRouter
from app.runtime import Runtime
from app.prompt_engine import Skill
from app.api.rag import get_doc_service
from app.core.user_context import current_user_id
import json
import asyncio

router = APIRouter()

# Smart router: Gemini primary, Groq fallback (activates when GROQ_API_KEY is set).
smart_router = SmartRouter()

# Dependency to get GeminiProvider directly for streaming
def get_gemini_provider() -> GeminiProvider:
    return GeminiProvider()

# Dependency to get ConversationManager (overridden in main.py with runtime-backed instance)
def get_conversation_manager() -> ConversationManager:
    return ConversationManager(runtime=Runtime())


@router.post("/chat", response_model=ChatResponse)
async def chat(
    request: ChatRequest,
    conversation_manager: ConversationManager = Depends(get_conversation_manager),
):
    """
    Non-streaming chat endpoint. Processes the message through the runtime pipeline.
    """
    skill = Skill.QUICK
    try:
        skill = Skill(request.skill)
    except ValueError:
        skill = Skill.QUICK

    result = await asyncio.to_thread(
        conversation_manager.chat,
        request.message,
        skill=skill,
        user_id=request.user_id,
        session_id=request.session_id,
    )

    return ChatResponse(
        reply=result.reply,
        skill_used=result.skill_used,
        runtime=result.runtime,
    )


@router.post("/chat/stream")
async def chat_stream(
    request: ChatRequest,
):
    """
    Streaming chat endpoint with RAG + smart routing.
    Runs a document lookup first; if relevant content is found it is injected
    into the prompt so the model answers from the uploaded documents.
    Gemini is the primary model; if it fails (e.g. quota), Groq takes over.
    Yields SSE events in the format expected by the Flutter client:
        data: {"text": "..."}\n\n
    and terminates with:
        data: [DONE]\n\n
    """
    print(f"[CHAT API] Received streaming request: '{request.message}'")

    async def event_generator():
        try:
            doc_service = get_doc_service()
            knowledge = ""
            direct_answer = None
            try:
                check = doc_service.vector_store.collection.get(limit=1)
                has_docs = bool(check and check.get("documents") and len(check["documents"]) > 0)
                if has_docs:
                    rag_result = doc_service.query(request.message)
                    rag_type = rag_result.get("type", "none")
                    answer = rag_result.get("answer", "")
                    if rag_type in ("structured_answer", "aggregation_refused") and answer:
                        direct_answer = answer
                    elif answer:
                        knowledge = answer
                        source = rag_result.get("source") or rag_result.get("sources")
                        if source:
                            knowledge += f"\n[المصدر: {source}]"
                    print(f"[CHAT API] RAG hit: type={rag_type}, knowledge_len={len(knowledge)}")
            except Exception as e:
                print(f"[CHAT API] RAG lookup failed: {e}")

            if direct_answer:
                yield f"data: {json.dumps({'text': direct_answer})}\n\n"
            else:
                async for chunk in smart_router.stream(request.message, knowledge=knowledge):
                    yield f"data: {json.dumps({'text': chunk})}\n\n"
            yield "data: [DONE]\n\n"
        except Exception as e:
            print(f"[CHAT API] Streaming error: {e}")
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from app.models.chat import ChatRequest, ChatResponse
from app.services.conversation_manager import ConversationManager
from app.providers.gemini_provider import GeminiProvider
from app.runtime import Runtime
from app.prompt_engine import Skill
import json
import asyncio

router = APIRouter()

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
    gemini_provider: GeminiProvider = Depends(get_gemini_provider)
):
    """
    Streaming chat endpoint using Gemini 1.5 Flash.
    Yields SSE events in the format expected by the Flutter client:
        data: {"text": "..."}\n\n
    and terminates with:
        data: [DONE]\n\n
    """
    print(f"[CHAT API] Received streaming request: '{request.message}'")

    async def event_generator():
        try:
            async for chunk in gemini_provider.service.stream_evora_response(request.message):
                yield f"data: {json.dumps({'text': chunk})}\n\n"
            yield "data: [DONE]\n\n"
        except Exception as e:
            print(f"[CHAT API] Streaming error: {e}")
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")

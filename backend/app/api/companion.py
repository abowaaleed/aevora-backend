from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional
import json

from app.companion.models import CompanionState, CompanionTask
from app.companion.service import get_companion_service
from app.core.user_context import current_user_id

router = APIRouter()


class CompanionChatRequest(BaseModel):
    message: str


class CompanionTaskRequest(BaseModel):
    text: str
    due: Optional[str] = None


@router.get("/state", response_model=CompanionState)
async def companion_state():
    return get_companion_service().get_state()


@router.post("/chat")
async def companion_chat(request: CompanionChatRequest):
    """محادثة متدفقة (SSE) مع المساعد الشخصي — بذاكرة دائمة وسياق كامل."""

    async def event_generator():
        try:
            service = get_companion_service()
            async for chunk in service.chat(request.message):
                yield f"data: {json.dumps({'text': chunk})}\n\n"
            yield "data: [DONE]\n\n"
        except Exception as e:
            print(f"[COMPANION API] chat error: {e}")
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")


@router.post("/tasks", response_model=CompanionTask)
async def add_task(request: CompanionTaskRequest):
    return get_companion_service().add_task(request.text, request.due)


@router.post("/tasks/{task_id}/toggle", response_model=Optional[CompanionTask])
async def toggle_task(task_id: str):
    return get_companion_service().toggle_task(task_id)


@router.delete("/tasks/{task_id}")
async def delete_task(task_id: str):
    ok = get_companion_service().delete_task(task_id)
    return {"deleted": ok}


@router.post("/analyze")
async def run_analysis():
    """تحليل فوري للسلوك وتحديث الذاكرة (يُستخدم تلقائياً بعد كل رسائل أيضاً)."""
    service = get_companion_service()
    await service.run_analysis_async()
    return {"analyzed": True}


@router.post("/reset")
async def reset_companion():
    service = get_companion_service()
    service.reset()
    return {"reset": True}

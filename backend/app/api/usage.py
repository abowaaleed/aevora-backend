from fastapi import APIRouter
from app.core.user_context import current_user_id
from app.usage.service import get_usage_service

router = APIRouter()


@router.get("/")
async def usage_state():
    uid = current_user_id()
    return get_usage_service(uid or "anon").get_state()

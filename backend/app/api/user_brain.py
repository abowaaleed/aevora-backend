from fastapi import APIRouter, Depends
from app.user_brain.models import UserBrainProfile
from app.user_brain.service import UserBrainService
from main import get_user_brain_service


router = APIRouter()


@router.get("/profile", response_model=UserBrainProfile)
async def get_profile(
    user_id: str = "default_user",
    service: UserBrainService = Depends(get_user_brain_service)
):
    """Retrieve the User Brain profile."""
    return service.get_or_create_profile(user_id)


@router.post("/profile", response_model=UserBrainProfile)
async def update_profile(
    profile: UserBrainProfile,
    service: UserBrainService = Depends(get_user_brain_service)
):
    """Update or save the User Brain profile."""
    return service.save_profile(profile)

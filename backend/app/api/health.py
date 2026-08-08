from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()


class HealthResponse(BaseModel):
    status: str
    project: str
    version: str


@router.get("/", response_model=HealthResponse)
async def get_health():
    return HealthResponse(
        status="healthy",
        project="ايفورا",
        version="0.1.0"
    )

from fastapi import APIRouter, Depends
from typing import List
from app.memory.models import MemoryEntry
from app.memory.service import MemoryService
from main import get_memory_service


router = APIRouter()


@router.get("/", response_model=List[MemoryEntry])
async def get_memories(
    user_id: str = "default_user",
    service: MemoryService = Depends(get_memory_service)
):
    """Retrieve all memory entries for a user."""
    return service.get_memories(user_id)


@router.post("/", response_model=MemoryEntry)
async def add_memory(
    content: str,
    user_id: str = "default_user",
    service: MemoryService = Depends(get_memory_service)
):
    """Store a new memory entry."""
    return service.add_memory(user_id, content)


@router.delete("/{memory_id}")
async def delete_memory(
    memory_id: str,
    user_id: str = "default_user",
    service: MemoryService = Depends(get_memory_service)
):
    """Delete a memory entry."""
    success = service.delete_memory(user_id, memory_id)
    return {"success": success}

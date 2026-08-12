from __future__ import annotations

from typing import Any, Optional
from pydantic import BaseModel, Field


class CompanionMessage(BaseModel):
    role: str = Field(..., description="user | assistant")
    text: str
    ts: str = Field(..., description="ISO timestamp")


class CompanionTask(BaseModel):
    id: str
    text: str
    due: Optional[str] = None
    created: str
    completed: bool = False
    done_at: Optional[str] = None


class CompanionProfile(BaseModel):
    """What the companion knows about the user (built over time)."""

    name: Optional[str] = None
    english_level: Optional[str] = None  # مبتدئ | متوسط | متقدم
    goals: list[str] = Field(default_factory=list)
    interests: list[str] = Field(default_factory=list)
    known_facts: list[str] = Field(default_factory=list)
    last_corrections: list[str] = Field(
        default_factory=list, description="أحدث تصحيحات اللغة الإنجليزية"
    )
    vocabulary: list[str] = Field(default_factory=list)
    learning_stats: dict[str, Any] = Field(default_factory=dict)
    last_proactive_shown: Optional[str] = Field(
        default=None, description="آخر مرة عُرضت فيها بطاقة المبادرة"
    )
    created: str = ""
    updated: str = ""


class CompanionState(BaseModel):
    profile: CompanionProfile
    memories: list[str]
    tasks: list[CompanionTask]
    recent: list[CompanionMessage]
    summary: Optional[str] = None
    proactive: Optional[str] = None
    suggested_prompt: Optional[str] = None

from __future__ import annotations

from typing import Any, Optional
from pydantic import BaseModel, Field


class UserBrainProfile(BaseModel):
    """Long-term user identity and preference profile for personalization."""

    user_id: str = Field(..., description="Stable identifier for the user")
    display_name: Optional[str] = Field(default=None, description="Preferred display name")
    communication_style: Optional[str] = Field(default=None, description="Preferred tone or style")
    expertise_level: Optional[str] = Field(default=None, description="User expertise level")
    goals: list[str] = Field(default_factory=list, description="Long-term goals")
    current_projects: list[str] = Field(default_factory=list, description="Active projects")
    favorite_modes: list[str] = Field(default_factory=list, description="Preferred Aevora modes")
    preferences: dict[str, Any] = Field(default_factory=dict, description="Stable profile preferences")
    metadata: dict[str, Any] = Field(default_factory=dict, description="Additional profile metadata")

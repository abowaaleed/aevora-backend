"""
Data structures for the Prompt Engine — Simplified for Mustafeed.
"""

from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field


class Skill(str, Enum):
    """Only one skill for Mustafeed."""
    QUICK = "quick"
    PDF = "pdf"


class PromptContext(BaseModel):
    """Minimal context for prompt building."""
    relevant_knowledge: Optional[str] = Field(default=None, description="Retrieved document content")
    recent_messages: Optional[str] = Field(default=None, description="Recent conversation messages")
    summary: Optional[str] = Field(default=None)
    active_goal: Optional[str] = Field(default=None)
    entities: Optional[dict] = Field(default=None)
    unfinished_tasks: Optional[list[str]] = Field(default=None)
    execution_steps: Optional[list[str]] = Field(default=None)
    memory: Optional[str] = Field(default=None)
    plugins_data: Optional[str] = Field(default=None)
    user_brain_context: Optional[str] = Field(default=None)
    topic: Optional[str] = Field(default=None)
    extracted_entities: Optional[list[str]] = Field(default=None)
    user_correction: Optional[dict] = Field(default=None)
    learning_context: Optional[str] = Field(default=None)


class PromptComponents(BaseModel):
    """Individual prompt components."""
    system_prompt: str = Field(description="System-level instructions")
    skill_prompt: str = Field(default="", description="Skill-specific instructions")


class BuiltPrompt(BaseModel):
    """The final assembled prompt."""
    content: str = Field(description="The complete prompt text")

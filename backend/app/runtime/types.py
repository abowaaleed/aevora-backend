"""
Data structures for the Runtime Engine — Simplified for Mustafeed.
"""

from enum import Enum
from typing import Any, Optional
from pydantic import BaseModel, Field


class ProviderInfo(BaseModel):
    """Metadata about the provider used for generation."""
    name: str = Field(..., description="Provider identifier")
    model: Optional[str] = Field(default=None, description="Model identifier")
    endpoint: Optional[str] = Field(default=None, description="Provider endpoint")
    metadata: dict[str, Any] = Field(default_factory=dict)


class PromptStatistics(BaseModel):
    """Lightweight prompt statistics."""
    prompt_length: int = Field(default=0)
    user_message_length: int = Field(default=0)


class StageTiming(BaseModel):
    """Stage timing metadata."""
    name: str = Field(..., description="Stage name")
    status: str = Field(..., description="Status")
    duration_ms: Optional[float] = Field(default=None, description="Duration in ms")
    details: Optional[str] = Field(default=None)


class RuntimeMetadata(BaseModel):
    """Runtime metadata for inspection."""
    selected_skill: Optional[str] = Field(default=None)
    provider: Optional[ProviderInfo] = Field(default=None)
    prompt_statistics: Optional[PromptStatistics] = Field(default=None)
    stage_timings: list[StageTiming] = Field(default_factory=list)
    response_duration_ms: int = Field(default=0)


class StageStatus(str, Enum):
    """Status of a stage execution."""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


class RuntimeRequest(BaseModel):
    """Request model for runtime execution."""
    user_message: str = Field(..., description="The user's message")
    skill: Optional[str] = Field(default=None)
    mode: Optional[str] = Field(default=None)
    session_id: Optional[str] = Field(default=None)
    user_id: Optional[str] = Field(default=None)


class RuntimeResponse(BaseModel):
    """Response model for runtime execution."""
    reply: str = Field(..., description="The AI-generated response")
    skill_used: str = Field(..., description="The skill that was used")
    stages_executed: list[str] = Field(default_factory=list)
    runtime: Optional[RuntimeMetadata] = Field(default=None)


class StageResult(BaseModel):
    """Result of a single stage execution."""
    stage_name: str = Field(..., description="Stage name")
    status: StageStatus = Field(..., description="Status")
    output: Optional[Any] = Field(default=None)
    error: Optional[str] = Field(default=None)
    duration_ms: Optional[float] = Field(default=None)


class PipelineContext(BaseModel):
    """Context object passed through the pipeline."""
    request: RuntimeRequest = Field(..., description="The original request")
    skill: Optional[str] = Field(default=None)
    provider_info: Optional[ProviderInfo] = Field(default=None)
    built_prompt: Optional[str] = Field(default=None, description="Assembled prompt")
    ai_response: Optional[str] = Field(default=None, description="AI-generated response")
    relevant_knowledge: Optional[str] = Field(default=None, description="Retrieved document content")
    stage_results: list[StageResult] = Field(default_factory=list)
    direct_response: Optional[str] = Field(default=None, description="Direct response bypassing LLM")

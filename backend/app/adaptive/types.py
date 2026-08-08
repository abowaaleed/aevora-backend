"""
Data structures for the Adaptive Intelligence Engine.

This module defines the types and data structures used for adaptive
request analysis, following clean architecture principles.
"""

from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field


class IntentType(str, Enum):
    """Enumeration of detected user intents."""
    
    LEARNING = "learning"
    PROGRAMMING = "programming"
    RESEARCH = "research"
    CONVERSATION = "conversation"
    DECISION = "decision"
    TRAVEL = "travel"
    GENERAL = "general"


class ResponseStyle(str, Enum):
    """Enumeration of response length styles."""
    
    ULTRA_SHORT = "ultra_short"
    SHORT = "short"
    MEDIUM = "medium"
    LONG = "long"


class ThinkingMode(str, Enum):
    """Enumeration of thinking depth modes."""
    
    FAST = "fast"
    NORMAL = "normal"
    DEEP = "deep"


class ComplexityTier(str, Enum):
    """Enumeration of complexity tiers for pipeline optimization."""

    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class AdaptiveDecision(BaseModel):
    """Decision model for adaptive request analysis.
    
    This model contains all the adaptive intelligence decisions
    made by analyzing the user's request before prompt building.
    """
    
    intent: IntentType = Field(..., description="Detected user intent")
    thinking_mode: ThinkingMode = Field(..., description="Required thinking depth")
    response_style: ResponseStyle = Field(..., description="Preferred response length")
    need_memory: bool = Field(default=False, description="Whether memory retrieval is required")
    need_plugins: bool = Field(default=False, description="Whether plugin execution is required")
    complexity_score: float = Field(..., ge=0.0, le=1.0, description="Complexity score from 0.0 to 1.0")
    tier: ComplexityTier = Field(default=ComplexityTier.MEDIUM, description="Calculated complexity tier")
    confidence: float = Field(..., ge=0.0, le=1.0, description="Confidence in the analysis from 0.0 to 1.0")
    required_tools: list[str] = Field(default_factory=list, description="Matched/Required tools")
    execution_steps: list[str] = Field(default_factory=list, description="Step-by-step execution plan")
    
    class Config:
        """Pydantic configuration."""
        use_enum_values = True

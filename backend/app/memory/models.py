from pydantic import BaseModel, Field
from typing import Optional


class MemoryEntry(BaseModel):
    """
    Model representing a single memory item stored for a user.
    """
    id: str = Field(..., description="Unique memory identifier")
    user_id: str = Field(..., description="User identifier")
    content: str = Field(..., description="The memory content string")
    timestamp: str = Field(..., description="Timestamp of when the memory was stored")
    category: Optional[str] = Field(default=None, description="Category of memory (e.g. family, preferences, career)")
    subject: Optional[str] = Field(default=None, description="Subject of memory (e.g. father, favorite_club, first_job_city)")
    relation: Optional[str] = Field(default=None, description="Relation to the subject or user (e.g. name, location)")
    value: Optional[str] = Field(default=None, description="The specific value stored (e.g. Ali, Real Madrid, Riyadh)")
    importance: Optional[str] = Field(default="medium", description="Importance level (high, medium, low)")
    confidence: Optional[float] = Field(default=1.0, description="Confidence level of memory extraction")


from pydantic import BaseModel, Field
from app.prompt_engine import Skill
from app.runtime.types import RuntimeMetadata


class ChatRequest(BaseModel):
    """Request model for chat endpoint."""
    
    message: str = Field(..., description="The user's message")
    skill: str = Field(default="quick", description="The skill to use for this interaction")
    user_id: str | None = Field(default=None, description="Optional stable user identifier")
    session_id: str | None = Field(default=None, description="Optional session identifier")
    
    class Config:
        json_schema_extra = {
            "example": {
                "message": "Hello",
                "skill": "quick",
                "user_id": "default",
                "session_id": "session_1"
            }
        }


class ChatResponse(BaseModel):
    """Response model for chat endpoint."""
    
    reply: str = Field(..., description="The AI-generated reply")
    skill_used: str = Field(..., description="The skill used for the response")
    runtime: RuntimeMetadata | None = Field(default=None, description="Structured runtime metadata")
    
    class Config:
        json_schema_extra = {
            "example": {
                "reply": "أنا ايفورا. محرك الذكاء الاصطناعي يعمل.",
                "skill_used": "quick"
            }
        }

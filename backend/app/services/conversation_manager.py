from app.runtime import Runtime, RuntimeRequest, RuntimeResponse
from app.prompt_engine import Skill
from typing import Optional


class ConversationManager:
    """
    Conversation Manager for orchestrating AI interactions.
    
    This layer is now a thin wrapper around the Runtime Engine.
    All business logic has been moved to the Runtime's pipeline stages.
    The ConversationManager simply converts API requests to Runtime requests
    and returns the response.
    """

    def __init__(self, runtime: Runtime):
        """
        Initialize the Conversation Manager with a Runtime instance.
        
        Args:
            runtime: The Runtime Engine instance
        """
        self.runtime = runtime

    def chat(
        self,
        user_message: str,
        skill: Skill = Skill.QUICK,
        user_id: Optional[str] = None,
        session_id: Optional[str] = None
    ) -> RuntimeResponse:
        """
        Process a user message and generate a response.
        
        This method now delegates all processing to the Runtime Engine.
        The Runtime orchestrates the entire request lifecycle through
        its pipeline stages.
        
        Args:
            user_message: The message from the user
            skill: The skill to use for this interaction (defaults to Quick)
            user_id: Optional stable user identifier
            session_id: Optional session identifier
            
        Returns:
            The AI-generated response
        """
        # Create Runtime request
        skill_value = skill.value if hasattr(skill, "value") else skill
        request = RuntimeRequest(
            user_message=user_message,
            skill=skill_value if skill_value else None,
            mode=skill_value if skill_value else None,
            session_id=session_id,
            user_id=user_id
        )
        
        # Process through Runtime
        return self.runtime.process(request)

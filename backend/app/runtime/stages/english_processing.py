"""
English Processing Stage.

This stage uses the English Learning Engine to process English learning requests.
It runs before the Prompt Builder when the selected skill is English.
"""

from ..task import Stage
from ..types import PipelineContext, StageStatus
from ..context import ContextManager
from app.skills.english import EnglishEngine
from app.prompt_engine import Skill


class EnglishProcessingStage(Stage):
    """
    Stage for English learning processing.
    
    This stage uses the English Learning Engine to analyze the user's message,
    detect grammar mistakes, generate lessons and exercises, and track progress.
    It only runs when the selected skill is English.
    """
    
    def __init__(self, english_engine: EnglishEngine):
        """
        Initialize the English processing stage.
        
        Args:
            english_engine: The EnglishEngine instance
        """
        super().__init__("english_processing")
        self.english_engine = english_engine
    
    def execute(self, context: PipelineContext):
        """
        Execute English processing.
        
        Args:
            context: The pipeline context
            
        Returns:
            StageResult with the English learning result
        """
        # Check if the skill is English
        skill = ContextManager.get_skill(context)
        
        if skill != "english":
            # Skip if not English skill
            return self._create_result(
                status=StageStatus.SKIPPED,
                output="Skipped - skill is not English"
            )
        
        # Get user ID from session (use session_id as user_id)
        user_id = context.request.session_id or "default_user"
        
        # Process using English Engine
        english_result = self.english_engine.process(
            message=context.request.user_message,
            user_id=user_id
        )
        
        # Store the English result in context
        context.english_result = english_result
        
        return self._create_result(
            status=StageStatus.COMPLETED,
            output=english_result
        )

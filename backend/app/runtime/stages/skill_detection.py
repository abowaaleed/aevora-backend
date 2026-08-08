"""
Skill Detection Stage.

This stage detects or validates the skill to use for the current request.
For Sprint 2, it uses the skill from the request or defaults to 'quick'.
"""

from ..task import Stage
from ..types import PipelineContext, StageStatus
from ..context import ContextManager


class SkillDetectionStage(Stage):
    """
    Stage for detecting or validating the skill to use.
    
    For Sprint 2, this stage simply uses the skill from the request
    or defaults to 'quick'. In future sprints, this will implement
    automatic skill detection based on content analysis.
    """
    
    def __init__(self):
        """Initialize the skill detection stage."""
        super().__init__("skill_detection")
    
    def execute(self, context: PipelineContext):
        """
        Execute skill detection.
        
        Args:
            context: The pipeline context
            
        Returns:
            StageResult with the detected/validated skill
        """
        # For Sprint 2, use skill from request or default to 'quick'
        skill = context.request.skill or "quick"
        mode = context.request.mode

        # Dynamic Skill Promotion based on intent, mode and query content
        user_msg = (context.request.user_message or "").lower()
        from app.adaptive.types import IntentType
        intent = None
        if context.adaptive_decision:
            intent = context.adaptive_decision.intent
            
        if mode == "pdf" or skill == "pdf":
            skill = "pdf"
        elif mode == "general" or skill == "general":
            skill = "general"
        elif intent == IntentType.LEARNING or any(w in user_msg for w in ["درس", "تعلم", "تعليم", "قواعد", "إنجليزي", "لغة", "english lesson"]):
            if skill != "english":
                skill = "english"
        elif skill == "quick":
            # Upgrade quick mode to think mode for complex reasoning/research tasks
            reason_keywords = ["قارن", "لماذا", "استنتج", "حلل", "logic", "compare", "why", "كم عدد", "how many", "explain", "شرح"]
            if intent in [IntentType.RESEARCH, IntentType.DECISION] or any(w in user_msg for w in reason_keywords):
                skill = "think"
        
        # Set the skill in context
        ContextManager.set_skill(context, skill)
        
        return self._create_result(
            status=StageStatus.COMPLETED,
            output=skill
        )

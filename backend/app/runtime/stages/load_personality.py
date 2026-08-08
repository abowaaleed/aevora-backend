"""
Load Personality Stage (Placeholder).

This stage loads personality parameters for the current skill.
For Sprint 2, this is a placeholder. Personality will be implemented in a future sprint.
"""

from ..task import Stage
from ..types import PipelineContext, StageStatus


class LoadPersonalityStage(Stage):
    """
    Stage for loading personality (placeholder for Sprint 2).
    
    For Sprint 2, this stage is a placeholder. In future sprints, it will
    load personality parameters from the Personality Engine based on the
    active skill and user preferences.
    """
    
    def __init__(self):
        """Initialize the load personality stage."""
        super().__init__("load_personality")
    
    def execute(self, context: PipelineContext):
        """
        Execute personality loading (placeholder).
        
        Args:
            context: The pipeline context
            
        Returns:
            StageResult indicating the stage was skipped (placeholder)
        """
        # Placeholder for Sprint 2 - personality not implemented yet
        context.personality = None
        
        return self._create_result(
            status=StageStatus.SKIPPED,
            output="Personality not implemented in Sprint 2"
        )

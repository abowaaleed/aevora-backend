"""
Adaptive Analysis Stage.

This stage uses the Adaptive Intelligence Engine to analyze the user request
before prompt building. It determines intent, complexity, response style,
thinking mode, and other adaptive parameters using deterministic rules.
"""

from ..task import Stage
from ..types import PipelineContext, StageStatus
from app.adaptive import AdaptiveEngine


class AdaptiveAnalysisStage(Stage):
    """
    Stage for adaptive request analysis.
    
    This stage uses the Adaptive Intelligence Engine to analyze the user's
    request and determine optimal processing parameters. It runs before
    the Prompt Builder stage to provide adaptive intelligence.
    """
    
    def __init__(self, adaptive_engine: AdaptiveEngine):
        """
        Initialize the adaptive analysis stage.
        
        Args:
            adaptive_engine: The AdaptiveEngine instance
        """
        super().__init__("adaptive_analysis")
        self.adaptive_engine = adaptive_engine
    
    def execute(self, context: PipelineContext):
        """
        Execute adaptive analysis.
        
        Args:
            context: The pipeline context
            
        Returns:
            StageResult with the adaptive decision
        """
        # Analyze the user message using Adaptive Engine
        adaptive_decision = self.adaptive_engine.analyze(
            context.request.user_message,
            mode=context.request.mode
        )
        
        # Store the adaptive decision in context
        context.adaptive_decision = adaptive_decision
        
        return self._create_result(
            status=StageStatus.COMPLETED,
            output=adaptive_decision
        )

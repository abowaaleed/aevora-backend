"""
Context management for the Runtime Engine.

This module provides helper functions and utilities for managing pipeline context,
including context creation, validation, and data access.
"""

from .types import RuntimeRequest, PipelineContext


class ContextManager:
    """
    Manager for creating and manipulating pipeline contexts.
    
    This class provides utilities for creating contexts from requests,
    validating context state, and accessing context data safely.
    """
    
    @staticmethod
    def create_context(request: RuntimeRequest) -> PipelineContext:
        """
        Create a new pipeline context from a runtime request.
        
        Args:
            request: The runtime request to create context from
            
        Returns:
            A new PipelineContext initialized with the request
        """
        context = PipelineContext(request=request)
        context.skill = request.skill or request.mode or "quick"
        return context
    
    @staticmethod
    def validate_context(context: PipelineContext) -> bool:
        """
        Validate that the context is in a valid state.
        
        Args:
            context: The context to validate
            
        Returns:
            True if the context is valid, False otherwise
        """
        # Check that request is present
        if context.request is None:
            return False
        
        # Check that user message is present
        if not context.request.user_message:
            return False
        
        return True
    
    @staticmethod
    def get_skill(context: PipelineContext) -> str:
        """
        Get the skill from context with fallback.
        
        Args:
            context: The pipeline context
            
        Returns:
            The skill name, or 'quick' as default fallback
        """
        if context.skill:
            return context.skill
        
        if context.request.skill:
            return context.request.skill
        
        return "quick"
    
    @staticmethod
    def set_skill(context: PipelineContext, skill: str) -> None:
        """
        Set the skill in context.
        
        Args:
            context: The pipeline context
            skill: The skill name to set
        """
        context.skill = skill
    
    @staticmethod
    def get_stage_result(context: PipelineContext, stage_name: str):
        """
        Get the result of a specific stage.
        
        Args:
            context: The pipeline context
            stage_name: The name of the stage to get results for
            
        Returns:
            The StageResult if found, None otherwise
        """
        for result in context.stage_results:
            if result.stage_name == stage_name:
                return result
        return None
    
    @staticmethod
    def did_stage_succeed(context: PipelineContext, stage_name: str) -> bool:
        """
        Check if a specific stage succeeded.
        
        Args:
            context: The pipeline context
            stage_name: The name of the stage to check
            
        Returns:
            True if the stage succeeded, False otherwise
        """
        result = ContextManager.get_stage_result(context, stage_name)
        if result is None:
            return False
        status = result.status.value if hasattr(result.status, "value") else result.status
        return status == "completed"

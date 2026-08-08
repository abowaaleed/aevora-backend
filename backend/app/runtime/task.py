"""
Stage/Task abstraction for the Runtime Engine.

This module defines the interface for pipeline stages, allowing independent
stage implementations that can be registered and executed by the runtime.
"""

from abc import ABC, abstractmethod
from typing import Optional
from .types import PipelineContext, StageResult, StageStatus
import time


class Stage(ABC):
    """
    Abstract base class for pipeline stages.
    
    Each stage in the runtime pipeline must implement this interface.
    Stages are independent, single-responsibility components that
    perform a specific task in the request processing pipeline.
    """
    
    def __init__(self, name: str):
        """Initialize the stage with a name.
        
        Args:
            name: The unique name of this stage
        """
        self.name = name
    
    @abstractmethod
    def execute(self, context: PipelineContext) -> StageResult:
        """
        Execute the stage logic.
        
        This method contains the core logic for the stage. It reads from
        the context, performs its task, and writes results back to the context.
        
        Args:
            context: The pipeline context containing request data and stage outputs
            
        Returns:
            StageResult containing the execution status and output
        """
        pass
    
    def _create_result(
        self,
        status: StageStatus,
        output: Optional[object] = None,
        error: Optional[str] = None,
        duration_ms: Optional[float] = None
    ) -> StageResult:
        """Helper method to create a StageResult.
        
        Args:
            status: The execution status
            output: The output data from the stage
            error: Error message if stage failed
            duration_ms: Execution duration in milliseconds
            
        Returns:
            A StageResult object
        """
        return StageResult(
            stage_name=self.name,
            status=status,
            output=output,
            error=error,
            duration_ms=duration_ms
        )
    
    def execute_with_timing(self, context: PipelineContext) -> StageResult:
        """
        Execute the stage with timing measurement.
        
        This wrapper method times the execution and creates a result
        with the duration. It handles exceptions gracefully.
        
        Args:
            context: The pipeline context
            
        Returns:
            StageResult with timing information
        """
        start_time = time.time()
        
        try:
            result = self.execute(context)
            duration_ms = (time.time() - start_time) * 1000
            result.duration_ms = duration_ms
            return result
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            return self._create_result(
                status=StageStatus.FAILED,
                error=str(e),
                duration_ms=duration_ms
            )

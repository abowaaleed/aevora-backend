"""
Runtime Engine package.

This package provides the core runtime system for Aevora, including:
- Pipeline architecture for sequential stage execution
- Stage registration and management
- Context management for data flow between stages
- Main Runtime orchestrator for request processing

The Runtime Engine is the heart of Aevora, orchestrating the entire
request lifecycle through independent, registered stages.
"""

from .types import (
    StageStatus,
    RuntimeRequest,
    RuntimeResponse,
    StageResult,
    PipelineContext
)
from .task import Stage
from .registry import StageRegistry
from .pipeline import Pipeline
from .context import ContextManager
from .runtime import Runtime

__all__ = [
    "StageStatus",
    "RuntimeRequest",
    "RuntimeResponse",
    "StageResult",
    "PipelineContext",
    "Stage",
    "StageRegistry",
    "Pipeline",
    "ContextManager",
    "Runtime",
]

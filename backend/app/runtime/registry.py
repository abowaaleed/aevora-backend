"""
Stage registry for the Runtime Engine.

This module manages the registration and retrieval of pipeline stages.
It allows for dynamic stage registration, making it easy to add new stages
without modifying core runtime logic.
"""

from typing import Dict, List, Optional
from .task import Stage


class StageRegistry:
    """
    Registry for managing pipeline stages.
    
    This class maintains a collection of registered stages and provides
    methods to register, retrieve, and list stages. It enforces unique
    stage names and provides a clean interface for stage management.
    """
    
    def __init__(self):
        """Initialize an empty stage registry."""
        self._stages: Dict[str, Stage] = {}
    
    def register(self, stage: Stage) -> None:
        """
        Register a stage in the registry.
        
        Args:
            stage: The stage instance to register
            
        Raises:
            ValueError: If a stage with the same name already exists
        """
        if stage.name in self._stages:
            raise ValueError(f"Stage '{stage.name}' is already registered")
        
        self._stages[stage.name] = stage
    
    def get(self, name: str) -> Stage:
        """
        Retrieve a stage by name.
        
        Args:
            name: The name of the stage to retrieve
            
        Returns:
            The stage instance if found
            
        Raises:
            ValueError: If the stage is not registered
        """
        if name not in self._stages:
            raise ValueError(f"Stage '{name}' is not registered")
        return self._stages[name]
    
    def get_all(self) -> List[str]:
        """
        Get all registered stage names.
        
        Returns:
            List of all registered stage names
        """
        return self.get_names()
    
    def get_names(self) -> List[str]:
        """
        Get names of all registered stages.
        
        Returns:
            List of stage names
        """
        return list(self._stages.keys())
    
    def has(self, name: str) -> bool:
        """
        Check if a stage is registered.
        
        Args:
            name: The name of the stage to check
            
        Returns:
            True if the stage is registered, False otherwise
        """
        return name in self._stages
    
    def unregister(self, name: str) -> bool:
        """
        Unregister a stage by name.
        
        Args:
            name: The name of the stage to unregister
            
        Returns:
            True if the stage was unregistered, False if it wasn't found
        """
        if name in self._stages:
            del self._stages[name]
            return True
        return False
    
    def clear(self) -> None:
        """Clear all registered stages."""
        self._stages.clear()
    
    def count(self) -> int:
        """
        Get the number of registered stages.
        
        Returns:
            The count of registered stages
        """
        return len(self._stages)

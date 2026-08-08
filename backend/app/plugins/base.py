from abc import ABC, abstractmethod
from typing import Any, Dict


class BasePlugin(ABC):
    """
    Abstract base class for all Aevora plugins.
    Each plugin must implement its execution logic and metadata.
    """

    @property
    @abstractmethod
    def name(self) -> str:
        """The unique name of the plugin."""
        pass

    @property
    @abstractmethod
    def description(self) -> str:
        """A brief description of what the plugin does."""
        pass

    @abstractmethod
    def execute(self, **kwargs: Any) -> Dict[str, Any]:
        """
        Execute the plugin logic with the given arguments.
        
        Args:
            **kwargs: Arbitrary keyword arguments needed for plugin execution.
            
        Returns:
            Dict containing the execution results.
        """
        pass

from abc import ABC, abstractmethod
from typing import Protocol


class BaseProvider(ABC):
    """
    Abstract base class for AI model providers.
    All providers must implement the generate method.
    """

    @abstractmethod
    def generate(self, prompt: str, **kwargs) -> str:
        """
        Generate a response from the AI model.
        
        Args:
            prompt: The input prompt for the AI model
            
        Returns:
            The generated response text
        """
        pass

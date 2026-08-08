"""
System prompt handler.

This module handles loading and managing the system prompt,
which defines Aevora's core identity and behavior guidelines.
"""

from .loader import PromptLoader


class SystemPrompt:
    """Manages the system prompt for Aevora.
    
    The system prompt defines Aevora's core identity, behavioral guidelines,
    and fundamental rules that apply across all interactions. It is loaded
    from a markdown file and can be cached for performance.
    """
    
    def __init__(self, loader: PromptLoader):
        """Initialize the system prompt handler.
        
        Args:
            loader: PromptLoader instance for loading markdown files.
        """
        self.loader = loader
        self._cached_prompt: str | None = None
    
    def get(self) -> str:
        """Get the system prompt.
        
        This method loads the system prompt from the markdown file and caches it
        for subsequent calls to avoid repeated file I/O.
        
        Returns:
            The system prompt content as a string.
        """
        if self._cached_prompt is None:
            self._cached_prompt = self.loader.load_system_prompt()
        
        return self._cached_prompt
    
    def reload(self) -> str:
        """Force reload the system prompt from file.
        
        This method clears the cache and reloads the system prompt from the
        markdown file. Useful for development when prompts change frequently.
        
        Returns:
            The freshly loaded system prompt content.
        """
        self._cached_prompt = None
        return self.get()

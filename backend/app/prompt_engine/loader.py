"""
Prompt loader for reading markdown prompt files.

This module handles loading prompt content from markdown files in the prompts directory.
It follows clean architecture by separating file I/O from prompt logic.
"""

from pathlib import Path
from typing import Optional


class PromptLoader:
    """Loads prompt content from markdown files.
    
    This class is responsible for reading markdown files from the prompts directory
    and returning their content as strings. It handles file not found errors gracefully.
    """
    
    def __init__(self, prompts_dir: Optional[Path] = None):
        """Initialize the prompt loader.
        
        Args:
            prompts_dir: Path to the prompts directory. If None, uses default.
        """
        if prompts_dir is None:
            # Default to backend/app/prompts relative to this file
            self.prompts_dir = Path(__file__).parent.parent / "prompts"
        else:
            self.prompts_dir = prompts_dir
        
        # Ensure prompts directory exists
        if not self.prompts_dir.exists():
            raise FileNotFoundError(
                f"Prompts directory not found: {self.prompts_dir}"
            )
    
    def load(self, filename: str) -> str:
        """Load a prompt from a markdown file.
        
        Args:
            filename: Name of the markdown file (e.g., "system.md", "quick.md")
            
        Returns:
            The content of the markdown file as a string.
            
        Raises:
            FileNotFoundError: If the prompt file doesn't exist.
        """
        file_path = self.prompts_dir / filename
        
        if not file_path.exists():
            raise FileNotFoundError(
                f"Prompt file not found: {file_path}"
            )
        
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        return content
    
    def load_system_prompt(self) -> str:
        """Load the system prompt.
        
        Returns:
            The system prompt content.
        """
        return self.load("system.md")
    
    def load_skill_prompt(self, skill: str) -> str:
        """Load a skill-specific prompt.
        
        Args:
            skill: The skill name (e.g., "quick", "english", "programmer")
            
        Returns:
            The skill prompt content.
        """
        return self.load(f"{skill}.md")

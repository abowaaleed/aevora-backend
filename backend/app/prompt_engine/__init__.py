"""
Prompt Engine package.

This package handles all prompt-related functionality for Aevora, including:
- Loading prompts from markdown files
- Managing system and skill-specific prompts
- Building complete prompts for AI providers
- Following the prompt pipeline design

The Prompt Engine ensures that no prompts are hardcoded in the codebase,
following the principle that every prompt belongs in the Prompt Engine.
"""

from .types import Skill, PromptContext, PromptComponents, BuiltPrompt
from .loader import PromptLoader
from .system_prompt import SystemPrompt
from .skill_prompt import SkillPrompt
from .builder import PromptBuilder

__all__ = [
    "Skill",
    "PromptContext",
    "PromptComponents",
    "BuiltPrompt",
    "PromptLoader",
    "SystemPrompt",
    "SkillPrompt",
    "PromptBuilder",
]

"""
Skill prompt handler — Simplified for Mustafeed.
"""

from pathlib import Path
from .loader import PromptLoader
from .types import Skill


class SkillPrompt:
    """Manages skill-specific prompts. Falls back to system prompt if file missing."""

    def __init__(self, loader: PromptLoader):
        self.loader = loader
        self._cached_prompts: dict[str, str] = {}

    def get(self, skill: Skill) -> str:
        skill_name = skill.value if hasattr(skill, "value") else skill

        if skill_name not in self._cached_prompts:
            try:
                self._cached_prompts[skill_name] = self.loader.load_skill_prompt(skill_name)
            except FileNotFoundError:
                # Fallback to system prompt
                self._cached_prompts[skill_name] = self.loader.load_system_prompt()

        return self._cached_prompts[skill_name]

    def reload(self, skill: Skill) -> str:
        skill_name = skill.value if hasattr(skill, "value") else skill
        self._cached_prompts.pop(skill_name, None)
        return self.get(skill)

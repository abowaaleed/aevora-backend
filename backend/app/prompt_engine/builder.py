"""
Simplified prompt builder for Mustafeed.

Minimal prompt assembly — no skills, no memory, no corrections.
"""

from typing import Any
from .types import Skill, PromptContext, PromptComponents, BuiltPrompt
from .system_prompt import SystemPrompt


class PromptBuilder:
    """Simplified prompt builder for Mustafeed."""

    def __init__(self, system_prompt: SystemPrompt):
        self.system_prompt = system_prompt

    def build(self, user_message: str, context: dict[str, Any] | None = None) -> BuiltPrompt:
        """Build a minimal prompt."""
        system = self.system_prompt.get()
        prompt_parts = [system]

        if context:
            knowledge = context.get("relevant_knowledge")
            if knowledge:
                prompt_parts.append(f"المستندات المرفوعة:\n{knowledge}")

            recent = context.get("recent_messages")
            if recent:
                prompt_parts.append(f"المحادثة السابقة:\n{recent}")

        prompt_parts.append(f"المستخدم: {user_message}")

        return BuiltPrompt(content="\n\n".join(prompt_parts))

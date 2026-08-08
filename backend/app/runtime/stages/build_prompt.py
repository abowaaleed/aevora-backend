"""
Build Prompt Stage — Simplified for Mustafeed.

Builds a minimal, focused prompt: system + retrieved docs + conversation history + user query.
No skill detection, no English learning, no memory injection, no adaptive override.
"""

import json
from pathlib import Path
from ..task import Stage
from ..types import PipelineContext, StageStatus
from app.prompt_engine import PromptBuilder, Skill


def load_history(user_id: str, session_id: str = "default_session") -> list:
    key = f"{user_id}_{session_id}"
    path = Path(__file__).parent.parent.parent.parent / "data" / "history.json"
    if path.exists():
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f).get(key, [])
        except Exception:
            return []
    return []


def save_history(user_id: str, history: list, session_id: str = "default_session"):
    key = f"{user_id}_{session_id}"
    path = Path(__file__).parent.parent.parent.parent / "data" / "history.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        data = {}
        if path.exists():
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
        data[key] = history[-20:]
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass


class BuildPromptStage(Stage):
    """
    Minimal prompt builder for Mustafeed.
    
    Builds: system_prompt + retrieved_docs + recent_history + user_message
    """

    def __init__(self, prompt_builder: PromptBuilder):
        super().__init__("build_prompt")
        self.prompt_builder = prompt_builder

    def execute(self, context: PipelineContext):
        user_id = context.request.user_id or "default"
        session_id = context.request.session_id or "default_session"
        history = load_history(user_id, session_id)

        # Get last 6 messages for context
        recent = history[-6:] if history else []
        history_str = ""
        for msg in recent:
            role = "المستخدم" if msg["role"] == "user" else "ايفورا"
            history_str += f"{role}: {msg['content']}\n"

        # Build minimal prompt
        prompt_parts = []

        # 1. System prompt
        system = self.prompt_builder.system_prompt.get()
        prompt_parts.append(system)

        # 2. Retrieved documents
        if context.relevant_knowledge:
            prompt_parts.append(f"المستندات المرفوعة:\n{context.relevant_knowledge}")

        # 3. Conversation history
        if history_str.strip():
            prompt_parts.append(f"المحادثة السابقة:\n{history_str.strip()}")

        # 4. User message
        prompt_parts.append(f"المستخدم: {context.request.user_message}")

        final_prompt = "\n\n".join(prompt_parts)

        # Print prompt for debugging
        print(f"[PROMPT] Length: {len(final_prompt)} chars")
        print(f"[PROMPT] History turns: {len(recent)}")
        if context.relevant_knowledge:
            print(f"[PROMPT] Knowledge length: {len(context.relevant_knowledge)} chars")

        context.built_prompt = final_prompt

        return self._create_result(
            status=StageStatus.COMPLETED,
            output=final_prompt
        )

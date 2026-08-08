import json
import uuid
import datetime
from pathlib import Path
from typing import Optional, Dict, Any

from ..task import Stage
from ..types import PipelineContext, StageStatus

def get_sessions_file_path() -> Path:
    return Path(__file__).parent.parent.parent.parent / "data" / "sessions.json"

def load_session_state(session_id: str) -> Dict[str, Any]:
    path = get_sessions_file_path()
    if path.exists():
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f).get(session_id, {})
        except Exception:
            return {}
    return {}

def save_session_state(session_id: str, state: Dict[str, Any]):
    path = get_sessions_file_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        data = {}
        if path.exists():
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
        data[session_id] = state
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass


class ContextManagementStage(Stage):
    """
    Stage for updating and maintaining the active goal, entities,
    unfinished tasks, and summary across the conversation.
    """
    
    def __init__(self, ai_engine=None):
        super().__init__("context_management")
        self.ai_engine = ai_engine
        
    def execute(self, context: PipelineContext):
        session_id = context.request.session_id or "default_session"
        user_message = context.request.user_message
        
        # Skip context management for simple/general conversation to reduce latency and avoid entity corruption
        intent = "general"
        if context.adaptive_decision is not None:
            intent = getattr(context.adaptive_decision, "intent", "general")
            
        # If it's a simple lookup or general conversation, skip LLM context updates
        if intent in ["general", "conversation", "greeting", "quick"] or (context.adaptive_decision and not context.adaptive_decision.need_plugins):
            state = load_session_state(session_id)
            context.session_state = state
            return self._create_result(
                status=StageStatus.SKIPPED,
                output="Skipped context tracking for simple/general query"
            )
            
        # Load previous context state
        state = load_session_state(session_id)
        
        prev_goal = state.get("active_goal")
        prev_entities = state.get("entities", {})
        prev_tasks = state.get("unfinished_tasks", [])
        prev_summary = state.get("summary")
        
        # Try to resolve ai_engine if not injected
        ai_engine = self.ai_engine
        if not ai_engine:
            try:
                from app.services.ai_engine import AIEngine
                from app.providers.ollama_provider import OllamaProvider
                ai_engine = AIEngine(provider=OllamaProvider())
            except Exception:
                pass
                
        if ai_engine:
            # Build entities, tasks, summary strings for the prompt
            prev_entities_str = json.dumps(prev_entities)
            prev_tasks_str = json.dumps(prev_tasks)
            
            prompt = f"""You are a context tracking assistant. Your job is to update the conversation context state based on the user's message and the previous context state.

Previous Context State:
- Active Goal: {prev_goal}
- Tracked Entities: {prev_entities_str}
- Unfinished Tasks: {prev_tasks_str}
- Conversation Summary: {prev_summary}

User's New Message: "{user_message}"

Analyze the conversation and the user's message. Update the context state.
- "active_goal": The user's main active goal (e.g. "planning trip to Istanbul", "checking weather"). If the topic changed, update this to the new goal.
- "entities": Extracted variables/entities relevant to the goal (e.g. destination, duration, date, name). Merge new entities with the previous ones.
- "unfinished_tasks": List of remaining sub-tasks to achieve the goal (e.g. decide destination, decide duration, calculate cost). Remove tasks that are completed.
- "summary": A concise summary of the conversation up to this point, incorporating new developments.

Return a JSON object with:
- "active_goal" (string or null)
- "entities" (object/dictionary)
- "unfinished_tasks" (array of strings)
- "summary" (string or null)

Respond ONLY with valid JSON. Do not write any conversational text or markdown codeblocks like ```json.
"""
            try:
                response_str = ai_engine.generate_with_prompt(prompt).strip()
                if response_str.startswith("```"):
                    lines = response_str.split("\n")
                    if lines[0].startswith("```"):
                        lines = lines[1:]
                    if lines and lines[-1].strip() == "```":
                        lines = lines[:-1]
                    response_str = "\n".join(lines).strip()
                
                parsed = json.loads(response_str)
                state = {
                    "active_goal": parsed.get("active_goal"),
                    "entities": parsed.get("entities", {}),
                    "unfinished_tasks": parsed.get("unfinished_tasks", []),
                    "summary": parsed.get("summary")
                }
            except Exception as e:
                print(f"ContextManagementStage AI classification error: {e}")
                
        # If any fields are missing, ensure defaults
        if "entities" not in state:
            state["entities"] = prev_entities
        if "unfinished_tasks" not in state:
            state["unfinished_tasks"] = prev_tasks
        if "active_goal" not in state:
            state["active_goal"] = prev_goal
        if "summary" not in state:
            state["summary"] = prev_summary
            
        # Save updated context state
        save_session_state(session_id, state)
        
        # Set in pipeline context
        context.session_state = state
        
        return self._create_result(
            status=StageStatus.COMPLETED,
            output=state
        )

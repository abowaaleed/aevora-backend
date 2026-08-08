import json
import re
import datetime
import uuid
from ..task import Stage
from ..types import PipelineContext, StageStatus
from app.memory.models import MemoryEntry


class SaveMemoryStage(Stage):
    """
    Stage for saving memory.
    """
    
    def __init__(self, ai_engine=None):
        """Initialize the save memory stage."""
        super().__init__("save_memory")
        self.ai_engine = ai_engine
    
    def execute(self, context: PipelineContext):
        """
        Execute memory saving.
        
        Args:
            context: The pipeline context
            
        Returns:
            StageResult indicating the stage result
        """
        user_message = context.request.user_message.strip()
        
        from app.runtime.stages.trivial_check import is_trivial_input
        if is_trivial_input(user_message):
            user_id = context.request.user_id or "default"
            from main import get_memory_service
            memory_service = get_memory_service()
            memories_after = memory_service.get_memories(user_id)
            print(f"\n==================== [TRACE] Memory After Save (User: {user_id} - Skipped Trivial Input) ====================")
            if memories_after:
                for m in memories_after:
                    print(f"  - Category: {m.category}, Subject: {m.subject}, Value: {m.value}, Content: '{m.content}'")
            else:
                print("  (No memories stored)")
            print("=" * 80)
            
            return self._create_result(
                status=StageStatus.SKIPPED,
                output="Skipped saving memory: message is trivial"
            )
            
        # Check if the message is a question - if so, do not save it as a memory
        msg_lower = user_message.lower()
        if msg_lower.endswith("?") or msg_lower.endswith("؟") or any(msg_lower.startswith(w) for w in ["ما ", "من ", "اين ", "أين ", "كيف ", "هل ", "كم ", "what ", "who ", "where ", "how ", "which ", "is ", "do ", "can ", "are "]) or any(w in msg_lower for w in ["ما اسم", "من أين", "من اين", "النادي الذي", "ما النادي"]):
            # Print Memory After Save (even if skipped)
            user_id = context.request.user_id or "default"
            from main import get_memory_service
            memory_service = get_memory_service()
            memories_after = memory_service.get_memories(user_id)
            print(f"\n==================== [TRACE] Memory After Save (User: {user_id} - Skipped Question Save) ====================")
            if memories_after:
                for m in memories_after:
                    print(f"  - Category: {m.category}, Subject: {m.subject}, Value: {m.value}, Content: '{m.content}'")
            else:
                print("  (No memories stored)")
            print("=" * 80)
            
            return self._create_result(
                status=StageStatus.SKIPPED,
                output="Skipped saving memory: message is a question"
            )
        
        # Try to resolve ai_engine if not injected
        ai_engine = self.ai_engine
        if not ai_engine:
            try:
                from app.services.ai_engine import AIEngine
                from app.providers.ollama_provider import OllamaProvider
                ai_engine = AIEngine(provider=OllamaProvider())
            except Exception:
                pass
        
        extracted = None

        # 1. First, try fast rule-based matching
        arabic_patterns = [
            (r"(?:اسمي|الاسم|اسمِي)\s+(?:هو|يكون)?\s*([a-zA-Z\u0600-\u06FF\s]+)", "family", "user", "name", "high"),
            (r"(?:أحب|احب|أشجع|اشجع|شجّع|شجع)\s+(?:نادي|فريق|ناديي)?\s*([a-zA-Z\u0600-\u06FF\s]+)", "preferences", "favorite_club", None, "medium"),
            (r"(?:اسم التطبيق|التطبيق هو|اسم هذا التطبيق|اسم التطبيق هو)\s+(?:هو|يكون)?\s*([a-zA-Z\u0600-\u06FF\s]+)", "app_metadata", "application_name", "name", "high"),
            (r"(?:أعيش في|اعيش في|مدينتي|سكني في|أنا من|انا من)\s+([a-zA-Z\u0600-\u06FF\s]+)", "location", "current_city", "location", "high"),
        ]
        english_patterns = [
            (r"(?:my name is|i am)\s+([a-zA-Z\s]+)", "family", "user", "name", "high"),
            (r"(?:i like|i love|i support)\s+([a-zA-Z\s]+)", "preferences", "favorite_club", None, "medium"),
            (r"(?:app name is|the app is called)\s+([a-zA-Z\s]+)", "app_metadata", "application_name", "name", "high"),
            (r"(?:i live in|my city is)\s+([a-zA-Z\s]+)", "location", "current_city", "location", "high"),
        ]
        
        user_message_lower = user_message.lower()
        triggers = ["remember that", "remember:", "remember", "تذكر أن", "احفظ أن", "تذكر", "احفظ"]
        matched_trigger = None
        for t in triggers:
            if t in user_message_lower:
                matched_trigger = t
                break
        
        if matched_trigger:
            idx = user_message_lower.find(matched_trigger) + len(matched_trigger)
            content = user_message[idx:].strip(" :.,!?")
            cat = "preferences" if ("food" in content.lower() or "like" in content.lower()) else "family"
            sub = "favorite_food" if "food" in content.lower() else "user"
            rel = None
            if "father" in content.lower():
                cat = "family"
                sub = "father"
                rel = "name"
            elif "mother" in content.lower():
                cat = "family"
                sub = "mother"
                rel = "name"
            
            extracted = {
                "content": content,
                "category": cat,
                "subject": sub,
                "relation": rel,
                "value": content,
                "importance": "medium"
            }
        else:
            for pattern, cat, sub, rel, imp in arabic_patterns + english_patterns:
                m = re.search(pattern, user_message, re.IGNORECASE)
                if m:
                    val = m.group(1).strip(" :.,!?")
                    if val:
                        content_str = f"{cat.capitalize()}: {val}"
                        if cat == "family" and sub == "user":
                            if any(w in user_message for w in ["اسمي", "الاسم", "اسم"]):
                                content_str = f"الاسم: {val}"
                            else:
                                content_str = f"Name: {val}"
                        elif cat == "location":
                            if any(w in user_message for w in ["عيش", "أعيش", "اعيش", "مدينة", "سكن", "المدينة"]):
                                content_str = f"المدينة: {val}"
                            else:
                                content_str = f"Location: {val}"
                        elif cat == "preferences" and sub == "favorite_club":
                            if any(w in user_message for w in ["نادي", "أشجع", "اشجع", "فريق"]):
                                content_str = f"النادي المفضل: {val}"
                            else:
                                content_str = f"Likes: {val}"
                        elif cat == "app_metadata":
                            if "تطبيق" in user_message:
                                content_str = f"اسم التطبيق: {val}"
                            else:
                                content_str = f"App: {val}"
                        
                        extracted = {
                            "content": content_str,
                            "category": cat,
                            "subject": sub,
                            "relation": rel,
                            "value": val,
                            "importance": imp
                        }
                        break

        # 2. Fallback to LLM semantic extraction if no rules matched
        if not extracted and ai_engine:
            prompt = f"""You are an expert system that extracts personal user facts to store in a long-term memory system.
Analyze the following user message: "{user_message}"

Determine if it contains a long-term personal fact about the user that should be remembered (e.g. name, preferences, favorite club/food, career/job, family relationships, travel plans, application metadata).
If it DOES NOT contain a personal fact, return: {{"is_fact": false}}

If it DOES, return a JSON object with:
- "is_fact": true
- "content": A standardized, natural language representation of the memory in English (e.g. "My father's name is Ali", "My first job was in Riyadh", "I like Real Madrid")
- "category": The category (e.g. "family", "preferences", "career", "travel", "app_metadata", "location")
- "subject": The subject (e.g. "father", "mother", "favorite_club", "favorite_food", "first_job_city", "current_city", "birth_city", "application_name", "travel_plans")
- "relation": Optional relation field (e.g. "name", "location", "destination", or null)
- "value": The target value (e.g. "Ali", "Real Madrid", "Riyadh", "Jeddah", "Aevora")
- "importance": "high", "medium", or "low"

Example 1:
Message: "My father's name is Ali."
Response: {{"is_fact": true, "content": "My father's name is Ali.", "category": "family", "subject": "father", "relation": "name", "value": "Ali", "importance": "high"}}

Example 2:
Message: "أحب ريال مدريد"
Response: {{"is_fact": true, "content": "I like Real Madrid.", "category": "preferences", "subject": "favorite_club", "relation": null, "value": "Real Madrid", "importance": "medium"}}

Example 3:
Message: "I live in Riyadh."
Response: {{"is_fact": true, "content": "I live in Riyadh.", "category": "location", "subject": "current_city", "relation": "location", "value": "Riyadh", "importance": "high"}}

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
                if parsed.get("is_fact"):
                    extracted = parsed
            except Exception as e:
                print(f"Error parsing memory extraction JSON: {e}")
        
        if extracted:
            user_id = context.request.user_id or "default"
            from main import get_memory_service
            memory_service = get_memory_service()
            
            # Find and update/delete existing memories matching category + subject + relation
            existing = memory_service.get_memories(user_id)
            for entry in existing:
                match_cat = (entry.category == extracted["category"])
                match_sub = (entry.subject == extracted["subject"])
                match_rel = (entry.relation == extracted.get("relation"))
                if match_cat and match_sub and match_rel:
                    memory_service.delete_memory(user_id, entry.id)
            
            # Save new structured memory
            new_entry = MemoryEntry(
                id=f"mem_{uuid.uuid4().hex[:8]}",
                user_id=user_id,
                content=extracted["content"],
                timestamp=datetime.datetime.now().isoformat(),
                category=extracted["category"],
                subject=extracted["subject"],
                relation=extracted.get("relation"),
                value=extracted["value"],
                importance=extracted.get("importance", "medium"),
                confidence=1.0
            )
            memory_service.store.save(new_entry)
            
            # Print Memory After Save
            memories_after = memory_service.get_memories(user_id)
            print(f"\n==================== [TRACE] Memory After Save (User: {user_id}) ====================")
            for m in memories_after:
                print(f"  - Category: {m.category}, Subject: {m.subject}, Value: {m.value}, Content: '{m.content}'")
            print("=" * 80)
            
            return self._create_result(
                status=StageStatus.COMPLETED,
                output=f"Saved memory: {extracted['content']}"
            )
        
        # Print Memory After Save (even if skipped)
        user_id = context.request.user_id or "default"
        from main import get_memory_service
        memory_service = get_memory_service()
        memories_after = memory_service.get_memories(user_id)
        print(f"\n==================== [TRACE] Memory After Save (User: {user_id} - Skipped Save) ====================")
        if memories_after:
            for m in memories_after:
                print(f"  - Category: {m.category}, Subject: {m.subject}, Value: {m.value}, Content: '{m.content}'")
        else:
            print("  (No memories stored)")
        print("=" * 80)
        
        return self._create_result(
            status=StageStatus.SKIPPED,
            output="No memory saving trigger matched"
        )


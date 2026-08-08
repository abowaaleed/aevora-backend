"""
Reasoning Stage.

This stage performs advanced reasoning analysis on the user message, context, and memories.
"""

import re
from typing import List
from ..task import Stage
from ..types import PipelineContext, StageStatus
from app.memory.service import MemoryService


class ReasoningStage(Stage):
    """
    Reasoning Layer to analyze queries, filter context, and resolve conflicts.
    """

    def __init__(self, memory_service: MemoryService):
        super().__init__("reasoning")
        self.memory_service = memory_service

    def execute(self, context: PipelineContext):
        user_id = context.request.user_id or "default"
        session_id = context.request.session_id or "default_session"
        user_message = context.request.user_message

        # Load history
        from app.runtime.stages.build_prompt import load_history
        history = load_history(user_id, session_id)

        # 1. User Correction Detection
        correction_keywords = ["خطأ", "مخطئ", "غير صحيح", "ليس صحيح", "غلط", "أنت غلطان", "wrong", "incorrect", "not correct", "mistake", "أنت مخطئ"]
        is_correction = any(w in user_message.lower() for w in correction_keywords)
        
        user_correction = None
        if is_correction:
            # Extract last reply by Aevora to find the contradiction target
            last_reply = ""
            for msg in reversed(history):
                if msg.get("role") == "assistant":
                    last_reply = msg.get("content", "")
                    break
            user_correction = {
                "is_correction": True,
                "previous_answer": last_reply,
                "user_feedback": user_message
            }
            context.user_correction = user_correction
            print(f"[REASONING] User correction detected! Previous answer: '{last_reply}' | Feedback: '{user_message}'")

        # 2. Query Analyzer
        query_type = self._analyze_query(user_message)

        # 3. Topic Tracker
        active_topic = context.topic or self._track_topic(user_message, history)

        # 4. Preference Resolver
        self._resolve_preferences(user_id, user_message)

        # Reload memories
        memories = self.memory_service.get_memories(user_id)

        # 5. Conflict Resolver (using history statements to exclude stale memory)
        filtered_memories = self._resolve_conflicts(memories, history)

        # 6. Composite Facts Builder
        composite_memories = self._build_composite_facts(filtered_memories)

        # 7. Context Ranking & Scoring
        ranked_memories = self._rank_context(composite_memories, user_message, active_topic)

        # Select highest-scoring memories
        selected_content = []
        if ranked_memories:
            ranked_memories.sort(key=lambda x: x[1], reverse=True)
            for m, score in ranked_memories:
                if score >= 65:
                    selected_content.append(m.content)

        # Populate context variables
        context.reasoning_analysis = {
            "query_type": query_type,
            "active_topic": active_topic,
            "selected_memories": selected_content,
        }

        # Override context.memory for Prompt Builder
        if selected_content:
            context.memory = "Stored User Memory:\n" + "\n".join(
                f"{i+1}. {c}" for i, c in enumerate(selected_content)
            )
            context.selected_memory = selected_content[0]
        else:
            context.memory = None
            context.selected_memory = None

        return self._create_result(
            status=StageStatus.COMPLETED,
            output=f"Reasoning completed. Type: {query_type}, Topic: {active_topic}, Correction: {is_correction}"
        )

    def _analyze_query(self, query: str) -> str:
        query_lower = query.lower()
        
        # Memory Question
        memory_keywords = ["اسمي", "أنا من", "نادي", "أشجع", "اسم التطبيق", "تفضيل", "ما اسم", "من أين", "أي نادي", "who am i", "my name", "what is my name", "where am i from", "تشجع"]
        if any(w in query_lower for w in memory_keywords):
            return "Memory Question"
            
        # Calculation
        calc_keywords = ["+", "-", "*", "/", "احسب", "جمع", "طرح", "ضرب", "قسمة", "sum", "math", "calculate"]
        if any(w in query_lower for w in calc_keywords):
            return "Calculation"
            
        # Medical
        medical_keywords = ["طبي", "دواء", "علاج", "مرض", "ألم", "صداع", "مستشفى", "doctor", "medical", "medicine", "pain", "headache"]
        if any(w in query_lower for w in medical_keywords):
            return "Medical"
            
        # Travel
        travel_keywords = ["سفر", "سياحة", "فندق", "طيران", "رحلة", "إسطنبول", "تركيا", "travel", "trip", "hotel", "flight"]
        if any(w in query_lower for w in travel_keywords):
            return "Travel"
            
        # Plugin Request
        plugin_keywords = ["weather", "طقس", "درجة الحرارة", "حرارة"]
        if any(w in query_lower for w in plugin_keywords):
            return "Plugin Request"
            
        # Conversation Question
        conv_keywords = ["ماذا قلت", "آخر رسالة", "قبل قليل", "الرسالة السابقة", "what did you say", "last message", "previous"]
        if any(w in query_lower for w in conv_keywords):
            return "Conversation Question"
            
        # Reasoning
        reason_keywords = ["قارن", "لماذا", "استنتج", "حلل", "logic", "compare", "why"]
        if any(w in query_lower for w in reason_keywords):
            return "Reasoning"
            
        return "Knowledge"

    def _track_topic(self, query: str, history: list) -> str:
        text = query.lower()
        for msg in history[-3:]:
            text += " " + msg.get("content", "").lower()
            
        if any(w in text for w in ["أبي", "أخي", "عائلة", "father", "brother", "family", "أختي", "أمي"]):
            return "family"
        if any(w in text for w in ["سفر", "سياحة", "فندق", "رحلة", "إسطنبول", "travel", "trip", "flight"]):
            return "travel"
        if any(w in text for w in ["طبي", "دواء", "علاج", "صداع", "مرض", "pain", "headache", "doctor"]):
            return "medical"
        if any(w in text for w in ["أحب", "أفضل", "تفضيل", "قهوة", "like", "love", "favorite", "coffee"]):
            return "preferences"
            
        return "general"

    def _resolve_preferences(self, user_id: str, message: str):
        # Look for statements where user updates preferences like favorite drinks or hobbies
        # Example: "أصبحت أحب القهوة الباردة" when old was "أحب القهوة الساخنة"
        memories = self.memory_service.get_memories(user_id)
        
        # Check if the message contains a new preference on coffee
        if "قهوة" in message or "coffee" in message:
            # Determine new type: cold vs hot
            new_type = None
            if "بارد" in message or "cold" in message:
                new_type = "بارد"
            elif "ساخن" in message or "حار" in message or "hot" in message:
                new_type = "ساخن"
                
            if new_type:
                for m in memories:
                    # Find old coffee/drink preference
                    m_category = m.category or ""
                    if (m_category == "preferences" or "أحب" in m.content or "like" in m.content) and ("قهوة" in m.content or "coffee" in m.content):
                        old_type = "ساخن" if ("ساخن" in m.content or "hot" in m.content) else "بارد"
                        if old_type != new_type:
                            # Delete the stale memory
                            self.memory_service.delete_memory(user_id, m.id)

    def _resolve_conflicts(self, memories: list, history: list) -> list:
        # Check if conversation history contains a statement that contradicts stored memory
        # E.g., user said "أنا من الرياض" in the past, but in history they said "أنا من القصيم"
        if not history:
            return memories

        # Extract latest statement about location, name, or club from history
        latest_city = None
        for msg in reversed(history):
            if msg.get("role") == "user":
                content = msg.get("content", "")
                loc_match = re.search(r'(?:من|في|سكن|عيش|اعيش|أعيش)\s+([^\s؟?]+)', content)
                if loc_match:
                    latest_city = loc_match.group(1).strip()
                    break

        if latest_city:
            filtered = []
            for m in memories:
                # If memory represents location but values differ, exclude it
                m_category = m.category or ""
                if m_category == "location" and latest_city not in m.content:
                    continue
                filtered.append(m)
            return filtered

        return memories

    def _build_composite_facts(self, memories: list) -> list:
        # Merge individual family facts (e.g. "أبي علي", "أخي محمد") into a composite fact
        family_memories = [m for m in memories if (m.category == "family" or any(w in m.content for w in ["أبي", "أخي", "أختي", "أمي"]))]
        if len(family_memories) > 1:
            non_family = [m for m in memories if m not in family_memories]
            
            # Construct single composite memory
            family_statements = [m.content for m in family_memories]
            composite_content = "العائلة: " + "، ".join(family_statements)
            
            # Create a mock/composite MemoryEntry
            from app.memory.models import MemoryEntry
            composite_entry = MemoryEntry(
                id="composite_family",
                user_id=family_memories[0].user_id,
                category="family",
                content=composite_content,
                timestamp="2026-07-09T00:00:00"
            )
            return non_family + [composite_entry]
            
        return memories

    def _rank_context(self, memories: list, query: str, active_topic: str) -> List[tuple]:
        ranked = []
        for m in memories:
            score = 0.0
            category = m.category.lower() if m.category else ""
            content = m.content.lower() if m.content else ""
            
            # Category priority scoring
            if "name" in category:
                score += 100
            elif "family" in category:
                score += 95
            elif "location" in category or "city" in category:
                score += 90
            elif "preferences" in category or "hobby" in category or "likes" in category:
                score += 80
            elif "drink" in category or "food" in category:
                score += 60
            else:
                score += 50
                
            # Topic relevance alignment
            if active_topic == "travel" and ("location" in category or "سفر" in content or "القصيم" in content):
                score += 50
            elif active_topic == "family" and ("family" in category or "أبي" in content or "أخي" in content):
                score += 50
            elif active_topic == "medical" and ("medical" in category or "دواء" in content):
                score += 50
            elif active_topic == "preferences" and ("preferences" in category or "حب" in content or "أعشق" in content):
                score += 50
                
            # Query match bonus
            for word in query.lower().split():
                if word in content:
                    score += 30
                    
            ranked.append((m, score))
            
        return ranked

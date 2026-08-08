import json
import datetime
from typing import List, Optional, Dict, Any, Tuple
from app.memory.models import MemoryEntry


class MemoryResolver:
    """
    Memory Resolver component to classify queries, filter memories,
    rank candidates, and handle conflicts or low confidence.
    """

    def __init__(self, ai_engine=None):
        self.ai_engine = ai_engine

    def resolve(
        self,
        question: str,
        conversation: List[Dict[str, str]],
        memories: List[MemoryEntry]
    ) -> Tuple[Optional[MemoryEntry], float, str, Optional[str]]:
        """
        Receives:
            question: The user's message.
            conversation: Recent message history (list of dicts with role/content).
            memories: List of all stored MemoryEntry objects for the user.
            
        Returns:
            Tuple of (Best Memory Entry, Confidence, Reason, Clarification Question if low confidence)
        """
        if not memories:
            return None, 0.0, "No memories stored for this user.", None

        # Try to obtain ai_engine if not passed
        ai_engine = self.ai_engine
        if not ai_engine:
            try:
                from app.services.ai_engine import AIEngine
                from app.providers.ollama_provider import OllamaProvider
                ai_engine = AIEngine(provider=OllamaProvider())
            except Exception:
                pass

        # 1. First, try rule-based heuristic classification
        intent = "other"
        category = None
        subject = None
        relation = None
        
        recent_history_str = ""
        for msg in conversation[-5:]:
            role = msg.get("role", "user")
            recent_history_str += f"{role.capitalize()}: {msg.get('content', '')}\n"

        msg_lower = question.lower()
        # Check keywords/patterns for quick heuristic
        if any(w in msg_lower for w in ["father", "أب", "اب"]):
            intent = "memory_lookup"
            category = "family"
            subject = "father"
            relation = "name"
        elif any(w in msg_lower for w in ["mother", "أم", "ام"]):
            intent = "memory_lookup"
            category = "family"
            subject = "mother"
            relation = "name"
        elif any(w in msg_lower for w in ["app", "تطبيق", "أيفورا", "ايفورا"]):
            intent = "memory_lookup"
            category = "app_metadata"
            subject = "application_name"
        elif any(w in msg_lower for w in ["who am i", "من أنا", "من انا", "what is my name", "my name", "اسمي", "اسمك", "ما اسمي"]):
            intent = "memory_lookup"
            category = "family"
            subject = "user"
            relation = "name"
        elif any(w in msg_lower for w in ["live", "مدينتي", "أعيش", "اعيش", "أين", "اين", "من أين", "من اين", "القصيم"]):
            intent = "memory_lookup"
            category = "location"
            subject = "current_city"
        elif any(w in msg_lower for w in ["first job", "career", "عملت", "أول وظيفة", "اول وظيفة"]):
            intent = "memory_lookup"
            category = "career"
            subject = "first_job_city"
        elif any(w in msg_lower for w in ["club", "team", "نادي", "فريق", "أشجع", "اشجع", "شجع", "تشجع", "أحب", "احب"]):
            intent = "memory_lookup"
            category = "preferences"
            subject = "favorite_club"
        elif any(w in msg_lower for w in ["food", "أكل", "اكل", "طعام"]):
            intent = "memory_lookup"
            category = "preferences"
            subject = "favorite_food"
        elif any(w in msg_lower for w in ["travel", "plans", "سفر"]):
            intent = "memory_lookup"
            category = "travel"
            subject = "travel_plans"

        # 2. Classify the question intent using LLM if heuristics did not resolve it
        if intent == "other" or not (category or subject):
            if ai_engine:
                prompt = f"""You are an expert system that classifies user messages for memory lookup intent in a chatbot.
Analyze the user's message: "{question}"
And the recent conversation history:
{recent_history_str}

Determine if the user is asking a question about their own profile, preferences, name, relationships, location, first job, favorite club/food, app name, travel plans, or any other personal detail stored about them (intent = "memory_lookup").
If they are just chatting, learning English, greeting, or doing anything else, intent = "other".

Return a JSON object with:
- "intent": "memory_lookup" or "other"
- "category": The expected memory category (e.g. "family", "preferences", "career", "travel", "app_metadata", "location") or null
- "subject": The expected subject (e.g. "father", "mother", "favorite_club", "favorite_food", "first_job_city", "current_city", "birth_city", "application_name", "travel_plans", "user") or null
- "relation": Optional relation field (e.g. "name", "location", "destination") or null

Respond ONLY with valid JSON. No conversational text or markdown codeblocks.
"""
                try:
                    res = ai_engine.generate_with_prompt(prompt).strip()
                    if res.startswith("```"):
                        lines = res.split("\n")
                        if lines[0].startswith("```"):
                            lines = lines[1:]
                        if lines and lines[-1].strip() == "```":
                            lines = lines[:-1]
                        res = "\n".join(lines).strip()
                    
                    parsed = json.loads(res)
                    intent = parsed.get("intent", "other")
                    category = parsed.get("category")
                    subject = parsed.get("subject")
                    relation = parsed.get("relation")
                except Exception as e:
                    print(f"MemoryResolver classification error: {e}")


        if intent != "memory_lookup":
            # Fallback word matching if classified as "other" but has specific word overlap
            q_words = [w.strip("?,.:!\"'()[]{}") for w in question.lower().split() if len(w.strip("?,.:!\"'()[]{}")) > 2]
            best_overlap = None
            max_overlap = 0
            for m in memories:
                content_lower = (m.content or "").lower()
                overlap = sum(1 for w in q_words if w in content_lower)
                if overlap > max_overlap:
                    max_overlap = overlap
                    best_overlap = m
            if best_overlap and max_overlap > 0:
                return best_overlap, 1.0, "Word overlap fallback match.", None
            return None, 0.0, "Query is not classified as a memory lookup.", None

        # 2. Filter memories based on category and subject
        candidates = []
        for m in memories:
            score = 0.0
            if category and m.category and m.category.lower() == category.lower():
                score += 1.0
            if subject and m.subject and m.subject.lower() == subject.lower():
                score += 1.0
            if relation and m.relation and m.relation.lower() == relation.lower():
                score += 0.5

            if score > 0.0:
                candidates.append((m, score))


        if not candidates and not (category or subject):
            # If no direct category/subject match and no category/subject classified, try semantic word overlap fallback
            q_words = set(question.lower().split())
            for m in memories:
                content_words = set((m.content or "").lower().split())
                overlap = len(q_words.intersection(content_words))
                if overlap > 0:
                    candidates.append((m, 0.2 + (overlap * 0.05)))

        if not candidates:
            return None, 0.0, f"No memories found matching category '{category}' and subject '{subject}'.", None

        # 3. Rank matching memories using Importance, Recency, Confidence
        ranked_candidates = []
        for m, base_score in candidates:
            score = base_score
            
            # Semantic / word overlap with the specific question + context
            overlap_score = 0.0
            all_text = (question + " " + recent_history_str).lower()
            words_in_mem = (m.content + " " + str(m.value)).lower().split()
            overlap_count = sum(1 for w in words_in_mem if w in all_text and len(w) > 2)
            overlap_score = min(0.3, overlap_count * 0.05)
            score += overlap_score

            # Importance
            imp = (m.importance or "medium").lower()
            if imp == "high":
                score += 0.2
            elif imp == "medium":
                score += 0.1

            # Recency (using ISO timestamp)
            try:
                dt = datetime.datetime.fromisoformat(m.timestamp)
                now = datetime.datetime.now()
                age_days = (now - dt).days
                recency_bonus = max(0.0, 0.1 - (age_days * 0.001))
                score += recency_bonus
            except Exception:
                pass

            # Confidence
            score += (m.confidence or 1.0) * 0.1

            ranked_candidates.append((m, score))

        # Sort descending by score
        ranked_candidates.sort(key=lambda x: x[1], reverse=True)

        # 4. Check for low confidence / conflicts (Step 4)
        best_candidate, best_score = ranked_candidates[0]
        
        # Calculate confidence
        if len(ranked_candidates) == 1:
            confidence = 1.0
        else:
            # If multiple, calculate confidence based on the margin between top two
            margin = best_score - ranked_candidates[1][1]
            if margin >= 0.4:
                confidence = 1.0
            else:
                confidence = max(0.0, margin / 0.4)

        # Check if there are multiple candidates with similar scores or same subject but different values
        conflicts = [c for c in ranked_candidates if c[0].id != best_candidate.id and c[0].category == best_candidate.category and c[0].subject == best_candidate.subject and c[0].value != best_candidate.value]
        
        if conflicts or (len(ranked_candidates) > 1 and confidence < 0.5):
            # We have a conflict or multiple close matches
            c_memory, c_score = ranked_candidates[1]
            m1_label = best_candidate.subject.capitalize() if best_candidate.subject else "Memory 1"
            m2_label = c_memory.subject.capitalize() if c_memory.subject else "Memory 2"
            
            clarification = f"I found two memories:\n\n{m1_label}: {best_candidate.value}\n{m2_label}: {c_memory.value}\n\nWhich one are you asking about?"
            return best_candidate, 0.4, "Low confidence due to multiple matching/conflicting memories.", clarification

        # Return best match
        return best_candidate, confidence, f"Successfully resolved memory (score: {best_score:.2f})", None

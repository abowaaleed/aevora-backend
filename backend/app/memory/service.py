import uuid
import datetime
from typing import List, Optional, Tuple
from app.memory.models import MemoryEntry
from app.memory.store import MemoryStore, InMemoryMemoryStore


class MemoryService:
    """
    Coordinates loading, saving, and formatting long-term user memories.
    """

    def __init__(self, store: Optional[MemoryStore] = None):
        self.store = store or InMemoryMemoryStore()
        from app.memory.resolver import MemoryResolver
        self.resolver = MemoryResolver()

    def get_memories(self, user_id: str) -> List[MemoryEntry]:
        """Retrieve all memories for the user."""
        return self.store.load_all(user_id)

    def add_memory(self, user_id: str, content: str) -> MemoryEntry:
        """Create and save a new memory."""
        # Simple extraction for direct API calls
        category = None
        subject = None
        relation = None
        value = content
        
        if ":" in content:
            parts = content.split(":", 1)
            prefix = parts[0].strip().lower()
            val = parts[1].strip()
            if any(w in prefix for w in ["الاسم", "name", "اسمي"]):
                category = "family"
                subject = "user"
                relation = "name"
                value = val
            elif any(w in prefix for w in ["نادي", "likes", "club", "فريق", "أشجع", "اشجع"]):
                category = "preferences"
                subject = "favorite_club"
                value = val
            elif any(w in prefix for w in ["المدينة", "location", "city", "سكن", "عيش", "live", "أعيش", "اعيش"]):
                category = "location"
                subject = "current_city"
                value = val
            elif any(w in prefix for w in ["وظيفة", "work", "job", "عمل", "أول وظيفة", "اول وظيفة"]):
                category = "career"
                subject = "first_job_city"
                value = val
            elif any(w in prefix for w in ["تطبيق", "app"]):
                category = "app_metadata"
                subject = "application_name"
                value = val

        if category and subject:
            existing = self.get_memories(user_id)
            for entry in existing:
                if entry.category == category and entry.subject == subject and entry.relation == relation:
                    self.delete_memory(user_id, entry.id)

        entry = MemoryEntry(
            id=f"mem_{uuid.uuid4().hex[:8]}",
            user_id=user_id,
            content=content.strip(),
            timestamp=datetime.datetime.now().isoformat(),
            category=category,
            subject=subject,
            relation=relation,
            value=value,
            importance="medium",
            confidence=1.0
        )
        self.store.save(entry)
        return entry

    def delete_memory(self, user_id: str, memory_id: str) -> bool:
        """Delete a specific memory."""
        return self.store.delete(user_id, memory_id)

    def resolve_memory(
        self,
        user_id: str,
        question: str,
        conversation: List[dict]
    ) -> Tuple[Optional[MemoryEntry], float, str, Optional[str]]:
        """Resolve the best matching memory using MemoryResolver."""
        memories = self.get_memories(user_id)
        return self.resolver.resolve(question, conversation, memories)

    def build_memory_context(self, user_id: str, user_message: Optional[str] = None) -> Optional[str]:
        """
        Retrieves all memories for a user and constructs a combined text context
        to be injected into the prompt.
        """
        if not user_message:
            memories = self.get_memories(user_id)
            if not memories:
                return None
            parts = []
            for i, m in enumerate(memories, 1):
                parts.append(f"{i}. {m.content}")
            return "Stored User Memory:\n" + "\n".join(parts)

        best_memory, confidence, reason, clarification = self.resolve_memory(user_id, user_message, [])
        if best_memory and confidence >= 0.5:
            return f"Stored User Memory:\n1. {best_memory.content}"
        return None


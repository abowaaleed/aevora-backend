from abc import ABC, abstractmethod
from typing import List, Optional
from app.memory.models import MemoryEntry


class MemoryStore(ABC):
    """
    Interface for memory persistence.
    """

    @abstractmethod
    def save(self, entry: MemoryEntry) -> None:
        pass

    @abstractmethod
    def load_all(self, user_id: str) -> List[MemoryEntry]:
        pass

    @abstractmethod
    def delete(self, user_id: str, memory_id: str) -> bool:
        pass


import json
import os
from pathlib import Path

class InMemoryMemoryStore(MemoryStore):
    """
    In-memory implementation of the memory store with JSON file persistence.
    """

    def __init__(self):
        self._file_path = Path(__file__).parent.parent.parent / "data" / "memories.json"
        self._file_path.parent.mkdir(parents=True, exist_ok=True)
        self._memories: dict[str, List[MemoryEntry]] = {}
        if self._file_path.exists():
            self._load_from_file()
            if "default" not in self._memories or "default_user" not in self._memories:
                self._seed_memories()
                self._save_to_file()
        else:
            self._seed_memories()
            self._save_to_file()

    def _load_from_file(self):
        try:
            with open(self._file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                for user_id, entries in data.items():
                    self._memories[user_id] = [MemoryEntry(**entry) for entry in entries]
        except Exception:
            self._memories = {}
            self._seed_memories()

    def _save_to_file(self):
        try:
            data = {}
            for user_id, entries in self._memories.items():
                data[user_id] = [entry.model_dump() for entry in entries]
            with open(self._file_path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
        except Exception:
            pass

    def _seed_memories(self):
        import datetime
        now_str = datetime.datetime.now().isoformat()
        
        for default_user in ["default", "default_user"]:
            self._memories[default_user] = [
                MemoryEntry(
                    id=f"mem_1_{default_user}",
                    user_id=default_user,
                    content="User prefers deep programming explanations using Clean Architecture and Flutter.",
                    timestamp=now_str
                ),
                MemoryEntry(
                    id=f"mem_2_{default_user}",
                    user_id=default_user,
                    content="User is practicing English for professional software presentations.",
                    timestamp=now_str
                )
            ]

    def save(self, entry: MemoryEntry) -> None:
        if entry.user_id not in self._memories:
            self._memories[entry.user_id] = []
        # Check if already exists to update
        existing = next((m for m in self._memories[entry.user_id] if m.id == entry.id), None)
        if existing:
            self._memories[entry.user_id].remove(existing)
        self._memories[entry.user_id].append(entry)
        self._save_to_file()

    def load_all(self, user_id: str) -> List[MemoryEntry]:
        return self._memories.get(user_id, []).copy()

    def delete(self, user_id: str, memory_id: str) -> bool:
        if user_id in self._memories:
            original_len = len(self._memories[user_id])
            self._memories[user_id] = [m for m in self._memories[user_id] if m.id != memory_id]
            if len(self._memories[user_id]) < original_len:
                self._save_to_file()
                return True
        return False

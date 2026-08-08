from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional

from .models import UserBrainProfile


class UserBrainStore(ABC):
    """Storage abstraction for the User Brain."""

    @abstractmethod
    def save(self, profile: UserBrainProfile) -> None:
        raise NotImplementedError

    @abstractmethod
    def load(self, user_id: str) -> Optional[UserBrainProfile]:
        raise NotImplementedError


import json
from pathlib import Path

class InMemoryUserBrainStore(UserBrainStore):
    """Simple in-memory implementation with JSON file persistence."""

    def __init__(self) -> None:
        self._file_path = Path(__file__).parent.parent.parent / "data" / "user_brain.json"
        self._file_path.parent.mkdir(parents=True, exist_ok=True)
        self._profiles: dict[str, UserBrainProfile] = {}
        if self._file_path.exists():
            self._load_from_file()

    def _load_from_file(self):
        try:
            with open(self._file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                for user_id, profile_dict in data.items():
                    self._profiles[user_id] = UserBrainProfile(**profile_dict)
        except Exception:
            self._profiles = {}

    def _save_to_file(self):
        try:
            data = {user_id: p.model_dump() for user_id, p in self._profiles.items()}
            with open(self._file_path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
        except Exception:
            pass

    def save(self, profile: UserBrainProfile) -> None:
        self._profiles[profile.user_id] = profile
        self._save_to_file()

    def load(self, user_id: str) -> Optional[UserBrainProfile]:
        profile = self._profiles.get(user_id)
        if profile is None:
            return None
        return profile.model_copy(deep=True)

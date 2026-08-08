from pydantic import BaseModel, Field
from typing import List, Dict, Optional
import datetime
import json
from pathlib import Path

class LearningMistake(BaseModel):
    user_id: str
    mistake_type: str
    example_sentence: str
    corrected_sentence: str
    timestamp: str
    occurrence_count: int = 1

class LearningMemory:
    """
    Persistent store for tracking user language learning mistakes.
    """
    def __init__(self):
        self._file_path = Path(__file__).parent.parent.parent.parent / "data" / "learning_mistakes.json"
        self._file_path.parent.mkdir(parents=True, exist_ok=True)
        self._mistakes: Dict[str, List[LearningMistake]] = {}
        if self._file_path.exists():
            self._load()

    def _load(self):
        try:
            with open(self._file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                for user_id, entries in data.items():
                    self._mistakes[user_id] = [LearningMistake(**e) for e in entries]
        except Exception:
            self._mistakes = {}

    def _save(self):
        try:
            data = {uid: [m.model_dump() for m in entries] for uid, entries in self._mistakes.items()}
            with open(self._file_path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
        except Exception:
            pass

    def record_mistake(self, user_id: str, mistake_type: str, original: str, correction: str):
        """
        Record or update a grammar mistake.
        """
        if user_id not in self._mistakes:
            self._mistakes[user_id] = []

        # Check for existing mistake_type for this user
        # We normalize mistake_type to lowercase for better matching
        m_type_norm = mistake_type.lower().strip()
        existing = next((m for m in self._mistakes[user_id] if m.mistake_type.lower() == m_type_norm), None)

        if existing:
            existing.occurrence_count += 1
            existing.timestamp = datetime.datetime.now().isoformat()
            existing.example_sentence = original
            existing.corrected_sentence = correction
        else:
            new_mistake = LearningMistake(
                user_id=user_id,
                mistake_type=mistake_type,
                example_sentence=original,
                corrected_sentence=correction,
                timestamp=datetime.datetime.now().isoformat()
            )
            self._mistakes[user_id].append(new_mistake)

        self._save()

    def get_top_recurring_mistakes(self, user_id: str, limit: int = 3) -> List[LearningMistake]:
        """
        Returns the most frequent/recent recurring mistakes.
        """
        user_mistakes = self._mistakes.get(user_id, [])
        # Sort by occurrence_count desc, then timestamp desc
        sorted_mistakes = sorted(user_mistakes, key=lambda x: (x.occurrence_count, x.timestamp), reverse=True)
        return sorted_mistakes[:limit]

    def get_session_mistakes(self, user_id: str, session_start_time: datetime.datetime) -> List[LearningMistake]:
        """
        Returns mistakes recorded in the current session.
        """
        user_mistakes = self._mistakes.get(user_id, [])
        session_mistakes = [
            m for m in user_mistakes
            if datetime.datetime.fromisoformat(m.timestamp) >= session_start_time
        ]
        return sorted(session_mistakes, key=lambda x: x.timestamp, reverse=True)

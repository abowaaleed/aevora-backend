"""
UsageService — عدّاد استهلاك اليوم للخطط المجانية (Gemini / Groq).

يحصي عدد استدعاءات النماذج لكل مستخدم في اليوم، ويُحفظ محلياً في
data/users/{uid}/usage.json مع نسخة سحابية (S3) حتى لا يُفقد مع إعادة البناء.

الحدود الافتراضية مبنية على الخطط المجانية الرسمية (2026):
  - Gemini (gemini-3.5-flash): ~1,500 طلب/يوم (15 دقيقة/دقيقة)
  - Groq (llama-3.3-70b-versatile): 1,000 طلب/يوم (30/دقيقة)
    وتفريغ Whisper: 2,000 صوت/يوم
يمكن تغييرها بمتغيرات البيئة GEMINI_DAILY_LIMIT / GROQ_DAILY_LIMIT.
"""

from __future__ import annotations

import os
import threading
import datetime
import json
from pathlib import Path
from typing import Dict, Optional

from app.rag.cloud_store import get_cloud_store

GEMINI_DAILY_LIMIT = int(os.getenv("GEMINI_DAILY_LIMIT", "1500"))
GROQ_DAILY_LIMIT = int(os.getenv("GROQ_DAILY_LIMIT", "1000"))
GROQ_STT_DAILY_LIMIT = int(os.getenv("GROQ_STT_DAILY_LIMIT", "2000"))
GEMINI_STT_DAILY_LIMIT = int(os.getenv("GEMINI_STT_DAILY_LIMIT", "1000"))


def _today() -> str:
    return datetime.datetime.now().strftime("%Y-%m-%d")


class UsageService:
    def __init__(self, uid: str):
        self.uid = uid
        self.cloud = get_cloud_store()
        self._lock = threading.Lock()
        self.dir = Path(__file__).parent.parent.parent / "data" / "users" / uid
        self.dir.mkdir(parents=True, exist_ok=True)
        self._load()

    def _path(self) -> Path:
        return self.dir / "usage.json"

    def _cloud_key(self) -> str:
        return f"users/{self.uid}/usage.json"

    def _load(self) -> None:
        default = {
            "date": _today(),
            "gemini_calls": 0,
            "groq_calls": 0,
            "stt_groq_calls": 0,
            "stt_gemini_calls": 0,
            "events": {},
        }
        data = None
        path = self._path()
        if path.exists():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except Exception as e:
                print(f"[USAGE] load error: {e}")
        if data is None and self.cloud.enabled:
            try:
                raw = self.cloud.download(self.uid, "usage.json")
                if raw:
                    data = json.loads(raw.decode("utf-8"))
                    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
            except Exception as e:
                print(f"[USAGE] cloud load error: {e}")
        self.data = {**default, **(data or {})}
        if self.data.get("date") != _today():
            self.data = default

    def _save(self) -> None:
        try:
            text = json.dumps(self.data, ensure_ascii=False, indent=2)
            self._path().write_text(text, encoding="utf-8")
            if self.cloud.enabled:
                try:
                    self.cloud.upload(self.uid, "usage.json", text.encode("utf-8"))
                except Exception as e:
                    print(f"[USAGE] cloud save error: {e}")
        except Exception as e:
            print(f"[USAGE] local save error: {e}")

    def _ensure_today(self) -> None:
        if self.data.get("date") != _today():
            self.data = {
                "date": _today(),
                "gemini_calls": 0,
                "groq_calls": 0,
                "stt_groq_calls": 0,
                "stt_gemini_calls": 0,
                "events": {},
            }

    def record_provider(self, kind: str) -> None:
        with self._lock:
            self._ensure_today()
            if kind == "gemini":
                self.data["gemini_calls"] += 1
            elif kind == "groq":
                self.data["groq_calls"] += 1
            elif kind == "stt_groq":
                self.data["stt_groq_calls"] += 1
            elif kind == "stt_gemini":
                self.data["stt_gemini_calls"] += 1
            self._save()

    def record_event(self, name: str) -> None:
        with self._lock:
            self._ensure_today()
            self.data.setdefault("events", {})
            self.data["events"][name] = self.data["events"].get(name, 0) + 1
            self._save()

    def get_state(self) -> dict:
        with self._lock:
            self._ensure_today()
            gemini = self.data.get("gemini_calls", 0)
            groq = self.data.get("groq_calls", 0)
            stt_groq = self.data.get("stt_groq_calls", 0)
            stt_gemini = self.data.get("stt_gemini_calls", 0)
            return {
                "date": self.data.get("date"),
                "gemini": {
                    "used": gemini,
                    "limit": GEMINI_DAILY_LIMIT,
                    "remaining": max(0, GEMINI_DAILY_LIMIT - gemini),
                },
                "groq": {
                    "used": groq,
                    "limit": GROQ_DAILY_LIMIT,
                    "remaining": max(0, GROQ_DAILY_LIMIT - groq),
                },
                "stt_groq": {
                    "used": stt_groq,
                    "limit": GROQ_STT_DAILY_LIMIT,
                    "remaining": max(0, GROQ_STT_DAILY_LIMIT - stt_groq),
                },
                "stt_gemini": {
                    "used": stt_gemini,
                    "limit": GEMINI_STT_DAILY_LIMIT,
                    "remaining": max(0, GEMINI_STT_DAILY_LIMIT - stt_gemini),
                },
                "events": self.data.get("events", {}),
            }


_services: Dict[str, UsageService] = {}


def get_usage_service(uid: str) -> UsageService:
    if uid not in _services:
        _services[uid] = UsageService(uid)
    return _services[uid]


def record_provider_usage(kind: str, uid: Optional[str]) -> None:
    """تسجيل استدعاء نموذج خارجي — يُتجاهل بلا هوية (مهام خادم خاصة)."""
    if not uid:
        return
    try:
        get_usage_service(uid).record_provider(kind)
    except Exception as e:
        print(f"[USAGE] record {kind} error: {e}")

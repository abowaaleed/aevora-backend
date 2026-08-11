import os
import hashlib
from contextvars import ContextVar

PUBLIC_MODE = os.environ.get("PUBLIC_MODE", "").strip().lower() in ("1", "true", "yes")

_current_user_id: ContextVar = ContextVar("current_user_id", default=None)
_current_gemini_key: ContextVar = ContextVar("current_gemini_key", default=None)
_current_groq_key: ContextVar = ContextVar("current_groq_key", default=None)
_current_email: ContextVar = ContextVar("current_email", default=None)


def current_user_id() -> str | None:
    return _current_user_id.get()


def current_gemini_key() -> str | None:
    return _current_gemini_key.get()


def current_groq_key() -> str | None:
    return _current_groq_key.get()


def current_email() -> str | None:
    return _current_email.get()


def user_has_keys() -> bool:
    return bool(current_gemini_key() or current_groq_key())


def derive_user_id(gemini_key: str | None, groq_key: str | None) -> str:
    raw = "|".join(
        [k for k in (gemini_key, groq_key) if k]
    )
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def set_request_context(
    user_id: str | None,
    gemini_key: str | None,
    groq_key: str | None,
    email: str | None,
) -> None:
    _current_user_id.set(user_id)
    _current_gemini_key.set(gemini_key)
    _current_groq_key.set(groq_key)
    _current_email.set(email)


def reset_request_context() -> None:
    _current_user_id.set(None)
    _current_gemini_key.set(None)
    _current_groq_key.set(None)
    _current_email.set(None)

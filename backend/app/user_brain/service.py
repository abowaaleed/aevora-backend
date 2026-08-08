from __future__ import annotations

from typing import Any, Optional

from .models import UserBrainProfile
from .store import UserBrainStore, InMemoryUserBrainStore


class UserBrainService:
    """Application service for reading and updating the User Brain."""

    def __init__(self, store: Optional[UserBrainStore] = None) -> None:
        self.store = store or InMemoryUserBrainStore()

    def get_or_create_profile(self, user_id: str) -> UserBrainProfile:
        existing = self.store.load(user_id)
        if existing is not None:
            return existing

        profile = UserBrainProfile(user_id=user_id)
        self.store.save(profile)
        return profile

    def save_profile(self, profile: UserBrainProfile) -> UserBrainProfile:
        self.store.save(profile)
        return profile

    def update_profile(
        self,
        user_id: str,
        *,
        display_name: Optional[str] = None,
        communication_style: Optional[str] = None,
        expertise_level: Optional[str] = None,
        goals: Optional[list[str]] = None,
        current_projects: Optional[list[str]] = None,
        favorite_modes: Optional[list[str]] = None,
        preferences: Optional[dict[str, Any]] = None,
        metadata: Optional[dict[str, Any]] = None,
        expert_level: Optional[str] = None,
    ) -> UserBrainProfile:
        profile = self.get_or_create_profile(user_id)
        if display_name is not None:
            profile.display_name = display_name
        if communication_style is not None:
            profile.communication_style = communication_style
        if expertise_level is not None:
            profile.expertise_level = expertise_level
        if expert_level is not None:
            profile.expertise_level = expert_level
        if goals is not None:
            profile.goals = goals
        if current_projects is not None:
            profile.current_projects = current_projects
        if favorite_modes is not None:
            profile.favorite_modes = favorite_modes
        if preferences is not None:
            profile.preferences.update(preferences)
        if metadata is not None:
            profile.metadata.update(metadata)
        return self.save_profile(profile)

    def build_context_summary(self, profile: UserBrainProfile) -> str:
        parts: list[str] = []
        if profile.display_name:
            parts.append(f"User display name: {profile.display_name}")
        if profile.communication_style:
            parts.append(f"Communication style: {profile.communication_style}")
        if profile.expertise_level:
            parts.append(f"Expertise level: {profile.expertise_level}")
        if profile.goals:
            parts.append(f"Goals: {', '.join(profile.goals)}")
        if profile.current_projects:
            parts.append(f"Current projects: {', '.join(profile.current_projects)}")
        if profile.favorite_modes:
            parts.append(f"Favorite modes: {', '.join(profile.favorite_modes)}")
        if profile.preferences:
            preference_text = ", ".join(f"{k}={v}" for k, v in profile.preferences.items())
            parts.append(f"Preferences: {preference_text}")
        return "\n".join(parts)

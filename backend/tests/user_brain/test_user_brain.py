import pytest

from app.prompt_engine import PromptBuilder
from app.runtime.types import PipelineContext, RuntimeRequest
from app.runtime.stages import LoadUserBrainStage
from app.user_brain import InMemoryUserBrainStore, UserBrainProfile, UserBrainService


class StubSystemPrompt:
    def get(self):
        return "System prompt"


class StubSkillPrompt:
    def get(self, skill):
        return f"Skill prompt for {skill}"


def test_in_memory_store_round_trips_profile():
    store = InMemoryUserBrainStore()
    profile = UserBrainProfile(
        user_id="user-1",
        display_name="Ada",
        goals=["learn python"],
        communication_style="direct",
        expertise_level="advanced",
        current_projects=["aevora"],
        favorite_modes=["quick"],
    )

    store.save(profile)
    loaded = store.load("user-1")

    assert loaded is not None
    assert loaded.display_name == "Ada"
    assert loaded.goals == ["learn python"]


def test_user_brain_service_updates_profile_and_returns_summary():
    service = UserBrainService(store=InMemoryUserBrainStore())

    profile = service.get_or_create_profile("user-1")
    profile.communication_style = "warm"
    service.save_profile(profile)

    updated = service.update_profile(
        "user-1",
        goals=["ship a product"],
        favorite_modes=["coach", "think"],
    )

    assert updated.goals == ["ship a product"]
    assert updated.favorite_modes == ["coach", "think"]
    assert updated.communication_style == "warm"
    assert "ship a product" in service.build_context_summary(updated)


def test_load_user_brain_stage_populates_context():
    service = UserBrainService(store=InMemoryUserBrainStore())
    service.update_profile(
        "user-1",
        goals=["write better emails"],
        expert_level="intermediate",
        communication_style="gentle",
    )
    stage = LoadUserBrainStage(service=service)
    context = PipelineContext(request=RuntimeRequest(user_message="Hello", user_id="user-1"))

    result = stage.execute(context)

    assert result.status.value == "completed"
    assert context.user_brain is not None
    assert context.user_brain.user_id == "user-1"
    assert "write better emails" in context.user_brain_context


def test_prompt_builder_includes_user_brain_context():
    builder = PromptBuilder(
        system_prompt=StubSystemPrompt(),
        skill_prompt=StubSkillPrompt(),
    )
    prompt = builder.build(
        skill="quick",
        user_message="Help me revise this email",
        context={
            "user_brain_context": "User is focused on clarity and concise writing.",
        },
    )

    assert "Retrieved Facts" in prompt.content
    assert "clarity and concise writing" in prompt.content

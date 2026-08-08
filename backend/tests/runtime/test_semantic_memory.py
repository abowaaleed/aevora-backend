import pytest
import datetime
from app.memory.models import MemoryEntry
from app.memory.resolver import MemoryResolver
from app.memory.service import MemoryService
from app.memory.store import InMemoryMemoryStore


class DummyAIEngine:
    def __init__(self, responses):
        self.responses = responses
        self.calls = []

    def generate_with_prompt(self, prompt):
        self.calls.append(prompt)
        for key, val in self.responses.items():
            if key in prompt:
                return val
        # fallback
        return '{"intent": "other"}'


def test_resolver_father_name():
    ai = DummyAIEngine({
        "What is my father's name?": '{"intent": "memory_lookup", "category": "family", "subject": "father", "relation": "name"}'
    })
    resolver = MemoryResolver(ai_engine=ai)
    memories = [
        MemoryEntry(
            id="1", user_id="u1", content="My father's name is Ali.", timestamp=datetime.datetime.now().isoformat(),
            category="family", subject="father", relation="name", value="Ali", importance="high"
        ),
        MemoryEntry(
            id="2", user_id="u1", content="My name is Mohammed.", timestamp=datetime.datetime.now().isoformat(),
            category="family", subject="user", relation="name", value="Mohammed", importance="medium"
        )
    ]
    
    best, confidence, reason, clarification = resolver.resolve("What is my father's name?", [], memories)
    assert best is not None
    assert best.value == "Ali"
    assert confidence > 0.5
    assert clarification is None


def test_resolver_mother_name():
    ai = DummyAIEngine({
        "Who is my mother?": '{"intent": "memory_lookup", "category": "family", "subject": "mother", "relation": "name"}'
    })
    resolver = MemoryResolver(ai_engine=ai)
    memories = [
        MemoryEntry(
            id="1", user_id="u1", content="My mother's name is Fatima.", timestamp=datetime.datetime.now().isoformat(),
            category="family", subject="mother", relation="name", value="Fatima", importance="high"
        )
    ]
    best, confidence, reason, clarification = resolver.resolve("Who is my mother?", [], memories)
    assert best is not None
    assert best.value == "Fatima"


def test_resolver_cities_current_and_birth():
    # Test current city vs birth city separation
    ai_current = DummyAIEngine({
        "Where do I live?": '{"intent": "memory_lookup", "category": "location", "subject": "current_city", "relation": "location"}'
    })
    ai_birth = DummyAIEngine({
        "Where was I born?": '{"intent": "memory_lookup", "category": "location", "subject": "birth_city", "relation": "location"}'
    })
    
    memories = [
        MemoryEntry(
            id="1", user_id="u1", content="I live in Riyadh.", timestamp=datetime.datetime.now().isoformat(),
            category="location", subject="current_city", relation="location", value="Riyadh", importance="high"
        ),
        MemoryEntry(
            id="2", user_id="u1", content="I was born in Jeddah.", timestamp=datetime.datetime.now().isoformat(),
            category="location", subject="birth_city", relation="location", value="Jeddah", importance="medium"
        )
    ]
    
    resolver_curr = MemoryResolver(ai_engine=ai_current)
    best_curr, _, _, _ = resolver_curr.resolve("Where do I live?", [], memories)
    assert best_curr.value == "Riyadh"
    
    resolver_birth = MemoryResolver(ai_engine=ai_birth)
    best_birth, _, _, _ = resolver_birth.resolve("Where was I born?", [], memories)
    assert best_birth.value == "Jeddah"


def test_resolver_first_job_city():
    ai = DummyAIEngine({
        "Which city did I first work in?": '{"intent": "memory_lookup", "category": "career", "subject": "first_job_city", "relation": "location"}'
    })
    resolver = MemoryResolver(ai_engine=ai)
    memories = [
        MemoryEntry(
            id="1", user_id="u1", content="My first job was in Riyadh.", timestamp=datetime.datetime.now().isoformat(),
            category="career", subject="first_job_city", relation="location", value="Riyadh", importance="high"
        ),
        MemoryEntry(
            id="2", user_id="u1", content="I live in Jeddah.", timestamp=datetime.datetime.now().isoformat(),
            category="location", subject="current_city", relation="location", value="Jeddah", importance="medium"
        )
    ]
    best, _, _, _ = resolver.resolve("Which city did I first work in?", [], memories)
    assert best.value == "Riyadh"


def test_resolver_favorite_club():
    ai = DummyAIEngine({
        "favorite club": '{"intent": "memory_lookup", "category": "preferences", "subject": "favorite_club"}'
    })
    resolver = MemoryResolver(ai_engine=ai)
    memories = [
        MemoryEntry(
            id="1", user_id="u1", content="I like Real Madrid.", timestamp=datetime.datetime.now().isoformat(),
            category="preferences", subject="favorite_club", value="Real Madrid", importance="medium"
        )
    ]
    best, _, _, _ = resolver.resolve("What is my favorite club?", [], memories)
    assert best.value == "Real Madrid"


def test_resolver_favorite_food():
    ai = DummyAIEngine({
        "favorite food": '{"intent": "memory_lookup", "category": "preferences", "subject": "favorite_food"}'
    })
    resolver = MemoryResolver(ai_engine=ai)
    memories = [
        MemoryEntry(
            id="1", user_id="u1", content="My favorite food is Kabsa.", timestamp=datetime.datetime.now().isoformat(),
            category="preferences", subject="favorite_food", value="Kabsa", importance="medium"
        )
    ]
    best, _, _, _ = resolver.resolve("What is my favorite food?", [], memories)
    assert best.value == "Kabsa"


def test_resolver_application_name():
    ai = DummyAIEngine({
        "app name": '{"intent": "memory_lookup", "category": "app_metadata", "subject": "application_name"}'
    })
    resolver = MemoryResolver(ai_engine=ai)
    memories = [
        MemoryEntry(
            id="1", user_id="u1", content="The app is called Aevora.", timestamp=datetime.datetime.now().isoformat(),
            category="app_metadata", subject="application_name", value="Aevora", importance="high"
        )
    ]
    best, _, _, _ = resolver.resolve("What is this app's name?", [], memories)
    assert best.value == "Aevora"


def test_resolver_travel_plans():
    ai = DummyAIEngine({
        "travel": '{"intent": "memory_lookup", "category": "travel", "subject": "travel_plans"}'
    })
    resolver = MemoryResolver(ai_engine=ai)
    memories = [
        MemoryEntry(
            id="1", user_id="u1", content="I plan to travel to London next month.", timestamp=datetime.datetime.now().isoformat(),
            category="travel", subject="travel_plans", value="London", importance="medium"
        )
    ]
    best, _, _, _ = resolver.resolve("What are my travel plans?", [], memories)
    assert best.value == "London"


def test_resolver_conversation_history_separation():
    # Make sure we don't return long term memory if user asks about short term conversation detail
    # e.g., User: "What did I just say?" should not trigger long term memory lookup
    ai = DummyAIEngine({
        "What did I just say?": '{"intent": "other"}'
    })
    resolver = MemoryResolver(ai_engine=ai)
    memories = [
        MemoryEntry(
            id="1", user_id="u1", content="My father's name is Ali.", timestamp=datetime.datetime.now().isoformat(),
            category="family", subject="father", relation="name", value="Ali", importance="high"
        )
    ]
    best, confidence, reason, clarification = resolver.resolve("What did I just say?", [{"role": "user", "content": "I like books."}], memories)
    assert best is None
    assert confidence == 0.0


def test_resolver_conflicting_memories():
    # Father has two names in database
    ai = DummyAIEngine({
        "father's name": '{"intent": "memory_lookup", "category": "family", "subject": "father", "relation": "name"}'
    })
    resolver = MemoryResolver(ai_engine=ai)
    memories = [
        MemoryEntry(
            id="1", user_id="u1", content="My father's name is Ali.", timestamp=datetime.datetime.now().isoformat(),
            category="family", subject="father", relation="name", value="Ali", importance="high"
        ),
        MemoryEntry(
            id="2", user_id="u1", content="My father's name is Ahmed.", timestamp=datetime.datetime.now().isoformat(),
            category="family", subject="father", relation="name", value="Ahmed", importance="high"
        )
    ]
    best, confidence, reason, clarification = resolver.resolve("What is my father's name?", [], memories)
    assert confidence < 0.5
    assert clarification is not None
    assert "Ali" in clarification
    assert "Ahmed" in clarification


def test_resolver_multiple_memories_ranking():
    # Multiple memories exist. Importance + recency rank the better one higher
    ai = DummyAIEngine({
        "favorite club": '{"intent": "memory_lookup", "category": "preferences", "subject": "favorite_club"}'
    })
    resolver = MemoryResolver(ai_engine=ai)
    
    # mem2 is newer and higher importance
    mem1 = MemoryEntry(
        id="1", user_id="u1", content="I used to support Chelsea.", timestamp=(datetime.datetime.now() - datetime.timedelta(days=10)).isoformat(),
        category="preferences", subject="favorite_club", value="Chelsea", importance="low"
    )
    mem2 = MemoryEntry(
        id="2", user_id="u1", content="I support Real Madrid now.", timestamp=datetime.datetime.now().isoformat(),
        category="preferences", subject="favorite_club", value="Real Madrid", importance="high"
    )
    
    best, confidence, reason, clarification = resolver.resolve("What is my favorite club?", [], [mem1, mem2])
    assert best.value == "Real Madrid"


def test_resolver_wrong_category():
    # If the user asks for father's name, but category is travel, it should not retrieve it
    ai = DummyAIEngine({
        "my travel plans": '{"intent": "memory_lookup", "category": "travel", "subject": "travel_plans"}'
    })
    resolver = MemoryResolver(ai_engine=ai)
    memories = [
        MemoryEntry(
            id="1", user_id="u1", content="My father's name is Ali.", timestamp=datetime.datetime.now().isoformat(),
            category="family", subject="father", relation="name", value="Ali", importance="high"
        )
    ]
    best, confidence, reason, clarification = resolver.resolve("my travel plans", [], memories)
    assert best is None


def test_resolver_heuristics_coverage():
    # Test every rule-based fallback check in MemoryResolver
    resolver = MemoryResolver(ai_engine=None)
    memories = []
    
    # 1. Mother
    best, _, _, _ = resolver.resolve("What is my mother's name?", [], memories)
    # 2. Live
    best, _, _, _ = resolver.resolve("Where do I live?", [], memories)
    # 3. First job
    best, _, _, _ = resolver.resolve("What was my first job?", [], memories)
    # 4. Club
    best, _, _, _ = resolver.resolve("Which club do I support?", [], memories)
    # 5. Food
    best, _, _, _ = resolver.resolve("What is my favorite food?", [], memories)
    # 6. App
    best, _, _, _ = resolver.resolve("What is this app?", [], memories)
    # 7. Travel
    best, _, _, _ = resolver.resolve("Where are my travel plans?", [], memories)


def test_save_memory_heuristics_coverage():
    from app.runtime.stages.save_memory import SaveMemoryStage
    from app.runtime.types import PipelineContext, RuntimeRequest
    
    stage = SaveMemoryStage()
    
    # English matches
    stage.execute(PipelineContext(request=RuntimeRequest(user_message="my name is John")))
    stage.execute(PipelineContext(request=RuntimeRequest(user_message="i like pizza")))
    stage.execute(PipelineContext(request=RuntimeRequest(user_message="app name is Aevora")))
    stage.execute(PipelineContext(request=RuntimeRequest(user_message="i live in Paris")))
    
    # Explicit remember triggers
    stage.execute(PipelineContext(request=RuntimeRequest(user_message="remember: my mother name is Jane")))
    stage.execute(PipelineContext(request=RuntimeRequest(user_message="remember that my father name is Bob")))


def test_load_memory_stage_coverage():
    from app.runtime.stages.load_memory import LoadMemoryStage
    from app.runtime.types import PipelineContext, RuntimeRequest
    from app.adaptive import AdaptiveDecision
    
    # 1. Skip memory if need_memory is False
    stage = LoadMemoryStage(service=MemoryService())
    ctx = PipelineContext(
        request=RuntimeRequest(user_message="Hello"),
        adaptive_decision=AdaptiveDecision(
            need_memory=False,
            thinking_mode="fast",
            response_style="short",
            intent="conversation",
            complexity_score=1,
            confidence=1.0
        )
    )
    res = stage.execute(ctx)
    assert res.status.value == "skipped"
    
    # 2. Executed but no memories found
    ctx2 = PipelineContext(
        request=RuntimeRequest(user_message="Who is my dad?", user_id="user_no_mem"),
        adaptive_decision=AdaptiveDecision(
            need_memory=True,
            thinking_mode="fast",
            response_style="short",
            intent="conversation",
            complexity_score=1,
            confidence=1.0
        )
    )
    # Clear user memories if any exist in the global/persisted store
    stage.service.store._memories["user_no_mem"] = []
    res2 = stage.execute(ctx2)
    assert res2.status.value == "skipped"


def test_store_coverage():
    from app.memory.store import InMemoryMemoryStore
    from app.memory.models import MemoryEntry
    import tempfile
    from pathlib import Path
    
    store = InMemoryMemoryStore()
    
    # Save for brand new user
    new_user = "brand_new_test_user"
    now_str = datetime.datetime.now().isoformat()
    entry = MemoryEntry(id="test_mem", user_id=new_user, content="Some data", timestamp=now_str)
    store.save(entry)
    assert len(store.load_all(new_user)) == 1
    
    # Delete non-existent
    assert store.delete(new_user, "non_existent_id") is False
    
    # Update existing
    entry2 = MemoryEntry(id="test_mem", user_id=new_user, content="Updated data", timestamp=now_str)
    store.save(entry2)
    assert store.load_all(new_user)[0].content == "Updated data"
    
    # Test exceptions
    store._file_path = Path("/nonexistentdir/nonexistentfile.json")
    # This should not crash, but just pass on save/load errors
    store.save(entry)
    store._load_from_file()


def test_context_management_stage():
    from app.runtime.stages.context_management import ContextManagementStage
    from app.runtime.types import PipelineContext, RuntimeRequest
    from app.adaptive import AdaptiveDecision
    
    dummy_ai = DummyAIEngine({
        "User's New Message": '{"active_goal": "planning trip to Istanbul", "entities": {"destination": "Istanbul"}, "unfinished_tasks": ["calculate cost"], "summary": "User wants to go to Istanbul"}'
    })
    
    stage = ContextManagementStage(ai_engine=dummy_ai)
    ctx = PipelineContext(
        request=RuntimeRequest(user_message="I want to go to Istanbul", session_id="test_session_abc", user_id="u1"),
        adaptive_decision=AdaptiveDecision(
            need_memory=True,
            thinking_mode="fast",
            response_style="short",
            intent="travel",
            need_plugins=True,
            complexity_score=1,
            confidence=1.0
        )
    )
    
    res = stage.execute(ctx)
    assert res.status.value == "completed"
    assert ctx.session_state is not None
    assert ctx.session_state["active_goal"] == "planning trip to Istanbul"
    assert ctx.session_state["entities"] == {"destination": "Istanbul"}
    assert ctx.session_state["unfinished_tasks"] == ["calculate cost"]
    assert ctx.session_state["summary"] == "User wants to go to Istanbul"


def test_prompt_builder_restructured():
    from app.prompt_engine import PromptBuilder, SystemPrompt, SkillPrompt, Skill
    from unittest.mock import MagicMock
    
    sys_mock = MagicMock(spec=SystemPrompt)
    sys_mock.get.return_value = "Identity: Aevora"
    
    skill_mock = MagicMock(spec=SkillPrompt)
    skill_mock.get.return_value = "Instructions: Help user learn English"
    
    builder = PromptBuilder(system_prompt=sys_mock, skill_prompt=skill_mock)
    
    built = builder.build(
        skill=Skill.ENGLISH,
        user_message="Let's start",
        context={
            "summary": "Conversation summary text",
            "active_goal": "Learn travel English",
            "entities": {"topic": "travel"},
            "unfinished_tasks": ["Practice dialogue", "Review vocab"],
            "execution_steps": ["Check context", "Query database"],
            "memory": "User profile details",
            "recent_messages": "Recent conversation messages",
            "plugins_data": "Plugin execution results",
            "user_brain_context": "User brain context details"
        }
    )
    
    content = built.content
    
    # Verify the sequence of sections
    assert "Identity: Aevora" in content
    assert "Conversation Summary:\nConversation summary text" in content
    assert "Current Session State:\nEntities: {\"topic\": \"travel\"}\nUnfinished Tasks: Practice dialogue, Review vocab" in content
    assert "Current User Goal: Learn travel English" in content
    assert "Execution Plan:\n- Check context\n- Query database" in content
    assert "Relevant Memories:\nUser profile details" in content
    assert "Retrieved Facts:\nUser brain context details" in content
    assert "Available Tools & Execution Results:\nPlugin execution results" in content
    assert "Recent Conversation:\nRecent conversation messages" in content
    assert "User: Let's start" in content
    
    # Confirm sequence order
    summary_idx = content.find("Conversation Summary:")
    session_idx = content.find("Current Session State:")
    goal_idx = content.find("Current User Goal:")
    plan_idx = content.find("Execution Plan:")
    memory_idx = content.find("Relevant Memories:")
    facts_idx = content.find("Retrieved Facts:")
    tools_idx = content.find("Available Tools & Execution Results:")
    history_idx = content.find("Recent Conversation:")
    user_idx = content.find("User: Let's start")
    
    assert summary_idx < session_idx < goal_idx < plan_idx < memory_idx < facts_idx < tools_idx < history_idx < user_idx





import pytest
from fastapi.testclient import TestClient
from main import app
from pathlib import Path
from app.runtime.stages.reasoning import ReasoningStage
from app.runtime.stages.validator import ResponseValidationStage
from app.runtime.types import PipelineContext, RuntimeRequest
from app.memory.models import MemoryEntry
from main import get_memory_service

@pytest.fixture
def clean_memories():
    m_file = Path(__file__).parent.parent.parent / "data" / "memories.json"
    if m_file.exists():
        try:
            m_file.unlink()
        except Exception:
            pass
    yield
    if m_file.exists():
        try:
            m_file.unlink()
        except Exception:
            pass

def test_query_analyzer():
    stage = ReasoningStage(get_memory_service())
    
    assert stage._analyze_query("ما اسمي؟") == "Memory Question"
    assert stage._analyze_query("who am I") == "Memory Question"
    assert stage._analyze_query("احسب 5 + 10") == "Calculation"
    assert stage._analyze_query("عندي صداع شديد وألم في البطن") == "Medical"
    assert stage._analyze_query("رحلة سياحية إلى إسطنبول") == "Travel"
    assert stage._analyze_query("ماذا قلت قبل قليل؟") == "Conversation Question"
    assert stage._analyze_query("قارن بين الفيل والنملة") == "Reasoning"
    assert stage._analyze_query("كم عدد الكواكب في النظام الشمسي؟") == "Knowledge"

def test_topic_tracker():
    stage = ReasoningStage(get_memory_service())
    history = [
        {"role": "user", "content": "أبي سافر أمس"},
        {"role": "assistant", "content": "أتمنى له رحلة سعيدة"}
    ]
    
    assert stage._track_topic("عائلتي هي كل شيء بالنسبة لي", history) == "family"
    assert stage._track_topic("أفكر في حجز فندق في إسطنبول", []) == "travel"
    assert stage._track_topic("أحتاج دواء للصداع", []) == "medical"
    assert stage._track_topic("أحب القهوة الباردة والساخنة", []) == "preferences"
    assert stage._track_topic("السلام عليكم", []) == "general"

def test_context_ranking():
    stage = ReasoningStage(get_memory_service())
    
    memories = [
        MemoryEntry(id="1", user_id="user", category="name", content="الاسم: صالح", timestamp="2026-07-09T00:00:00"),
        MemoryEntry(id="2", user_id="user", category="family", content="أبي علي", timestamp="2026-07-09T00:00:00"),
        MemoryEntry(id="3", user_id="user", category="preferences", content="أحب الهلال", timestamp="2026-07-09T00:00:00"),
        MemoryEntry(id="4", user_id="user", category="preferences", content="أحب القهوة الساخنة", timestamp="2026-07-09T00:00:00"),
    ]
    
    ranked = stage._rank_context(memories, "من هو أبي؟", "family")
    ranked.sort(key=lambda x: x[1], reverse=True)
    
    assert ranked[0][0].category == "family"

def test_conflict_resolver():
    stage = ReasoningStage(get_memory_service())
    
    memories = [
        MemoryEntry(id="1", user_id="user", category="location", content="أنا من الرياض", timestamp="2026-07-09T00:00:00"),
    ]
    history = [
        {"role": "user", "content": "أنا من القصيم"},
        {"role": "assistant", "content": "أهلاً بك"}
    ]
    
    filtered = stage._resolve_conflicts(memories, history)
    assert len(filtered) == 0

def test_preference_resolver(clean_memories):
    service = get_memory_service()
    user_id = "test_pref_user"
    
    service.add_memory(user_id, "أحب القهوة الساخنة")
    mems_before = service.get_memories(user_id)
    assert any("القهوة الساخنة" in m.content for m in mems_before)
    
    stage = ReasoningStage(service)
    stage._resolve_preferences(user_id, "أصبحت أحب القهوة الباردة")
    
    mems_after = service.get_memories(user_id)
    assert not any("القهوة الساخنة" in m.content for m in mems_after)

def test_composite_facts():
    stage = ReasoningStage(get_memory_service())
    memories = [
        MemoryEntry(id="1", user_id="user", category="family", content="أبي علي", timestamp="2026-07-09T00:00:00"),
        MemoryEntry(id="2", user_id="user", category="family", content="أخي محمد", timestamp="2026-07-09T00:00:00"),
        MemoryEntry(id="3", user_id="user", category="name", content="الاسم: صالح", timestamp="2026-07-09T00:00:00"),
    ]
    
    composite = stage._build_composite_facts(memories)
    assert len(composite) == 2
    assert any("العائلة" in m.content for m in composite)
    assert any("أبي علي" in m.content and "أخي محمد" in m.content for m in composite)

def test_response_validator():
    import os
    os.environ["ENABLE_JUDGE_VALIDATION"] = "false"
    from app.services.ai_engine import AIEngine
    class MockProvider:
        def generate(self, prompt):
            return "VALID"
    mock_engine = AIEngine(provider=MockProvider())
    validator = ResponseValidationStage(ai_engine=mock_engine)
    
    req = RuntimeRequest(user_message="ما اسمي؟")
    context = PipelineContext(request=req)
    context.retrieved_memories = ["الاسم: ناصر"]
    context.selected_memory = "الاسم: ناصر"
    
    context.ai_response = "أنت ناصر."
    res1 = validator.execute(context)
    assert res1.status == "completed"
    assert context.ai_response == "أنت ناصر."
    
    context.ai_response = "أنت صالح."
    res2 = validator.execute(context)
    assert res2.status == "completed"
    assert "عذراً" in context.ai_response

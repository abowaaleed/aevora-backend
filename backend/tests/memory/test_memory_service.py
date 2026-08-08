import pytest
from app.memory.service import MemoryService
from app.memory.store import InMemoryMemoryStore

def test_memory_service_selective_retrieval():
    store = InMemoryMemoryStore()
    user_id = "test_selective"
    # Clean any leftover memories from previous runs
    store._memories[user_id] = []
    service = MemoryService(store=store)
    
    # Add various memories
    service.add_memory(user_id, "الاسم: صالح")
    service.add_memory(user_id, "النادي المفضل: الهلال")
    service.add_memory(user_id, "المدينة: بريدة")
    service.add_memory(user_id, "اسم التطبيق: أيفورا")
    
    # 1. Test Name retrieval
    context_name = service.build_memory_context(user_id, "ما اسمي؟")
    assert context_name is not None
    assert "الاسم: صالح" in context_name
    assert "المدينة" not in context_name
    
    # 2. Test Club retrieval
    context_club = service.build_memory_context(user_id, "ما النادي الذي أشجعه؟")
    assert context_club is not None
    assert "النادي المفضل: الهلال" in context_club
    assert "الاسم" not in context_club

    # 3. Test App retrieval
    context_app = service.build_memory_context(user_id, "ما اسم هذا التطبيق؟")
    assert context_app is not None
    assert "اسم التطبيق: أيفورا" in context_app

    # 4. Test City retrieval
    context_city = service.build_memory_context(user_id, "أين أعيش؟")
    assert context_city is not None
    assert "المدينة: بريدة" in context_city

    # 5. Test Fallback word matching
    context_fallback = service.build_memory_context(user_id, "تحدث معي عن الهلال")
    assert context_fallback is not None
    assert "الهلال" in context_fallback

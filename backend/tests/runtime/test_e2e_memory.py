import pytest
from fastapi.testclient import TestClient
from main import app
import json
from pathlib import Path

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

def test_e2e_memory_save_update_retrieve(clean_memories):
    client = TestClient(app)
    user_id = "e2e_test_user"
    session_id = "session_e2e"
    
    # 1. Save fact: "اسمي صالح"
    payload = {
        "message": "اسمي صالح",
        "skill": "quick",
        "user_id": user_id,
        "session_id": session_id
    }
    response = client.post("/chat", json=payload)
    assert response.status_code == 200
    
    # Verify it was added to memory store
    from main import get_memory_service
    mems = get_memory_service().get_memories(user_id)
    assert any("الاسم: صالح" in m.content for m in mems)
    
    # 2. Update fact: "اسمي منصور" (Should overwrite old name)
    payload_update = {
        "message": "اسمي منصور",
        "skill": "quick",
        "user_id": user_id,
        "session_id": session_id
    }
    response_update = client.post("/chat", json=payload_update)
    assert response_update.status_code == 200
    
    # Verify it was updated in memory store
    mems_updated = get_memory_service().get_memories(user_id)
    assert any("الاسم: منصور" in m.content for m in mems_updated)
    assert not any("الاسم: صالح" in m.content for m in mems_updated)

    # 3. Simulate "restart backend" by creating a new TestClient and reloading
    new_client = TestClient(app)
    
    # 4. Ask question: "ما اسمي؟"
    payload_q = {
        "message": "ما اسمي؟",
        "skill": "quick",
        "user_id": user_id,
        "session_id": "session_new"
    }
    response_q = new_client.post("/chat", json=payload_q)
    assert response_q.status_code == 200
    res_q = response_q.json()
    print("E2E RETRIEVAL RESPONSE IS:", res_q)
    
    # Verify Runtime Inspector metadata lists "الاسم: منصور"
    metadata_q = res_q.get("runtime", {})
    assert any("الاسم: منصور" in m for m in metadata_q.get("loaded_memories", []))

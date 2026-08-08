import requests
import json
import uuid
import os
from pathlib import Path

BASE_URL = "http://127.0.0.1:8000"

def clean_memories():
    m_file = Path(__file__).parent.parent / "data" / "memories.json"
    if m_file.exists():
        try:
            m_file.unlink()
            print("Cleaned memories database.")
        except Exception as e:
            print(f"Error cleaning memories: {e}")

def send_chat(message: str, session_id: str):
    payload = {
        "message": message,
        "skill": "quick",
        "user_id": "nasser_test_user",
        "session_id": session_id
    }
    response = requests.post(f"{BASE_URL}/chat", json=payload)
    if response.status_code == 200:
        return response.json()
    else:
        raise Exception(f"Request failed: {response.text}")

def run_tests():
    clean_memories()
    
    print("\n" + "=" * 30 + " STARTING TEST SEQUENCE " + "=" * 30)
    session_id = f"session_{uuid.uuid4().hex[:6]}"
    print(f"Active Session: {session_id}")
    
    # 1. "اسمي ناصر"
    print("\n--- Step 1: اسمي ناصر ---")
    res1 = send_chat("اسمي ناصر", session_id)
    print(f"Reply: {res1['reply']}")
    
    # 2. "ما اسمي؟"
    print("\n--- Step 2: ما اسمي؟ ---")
    res2 = send_chat("ما اسمي؟", session_id)
    print(f"Reply: {res2['reply']}")
    
    # 3. "أنا من القصيم"
    print("\n--- Step 3: أنا من القصيم ---")
    res3 = send_chat("أنا من القصيم", session_id)
    print(f"Reply: {res3['reply']}")
    
    # 4. "من أين أنا؟"
    print("\n--- Step 4: من أين أنا؟ ---")
    res4 = send_chat("من أين أنا؟", session_id)
    print(f"Reply: {res4['reply']}")
    
    # 5. "أحب الهلال"
    print("\n--- Step 5: أحب الهلال ---")
    res5 = send_chat("أحب الهلال", session_id)
    print(f"Reply: {res5['reply']}")
    
    # 6. "ما النادي الذي أشجعه؟"
    print("\n--- Step 6: ما النادي الذي أشجعه؟ ---")
    res6 = send_chat("ما النادي الذي أشجعه؟", session_id)
    print(f"Reply: {res6['reply']}")
    
    # 7. "اسم التطبيق أيفورا"
    print("\n--- Step 7: اسم التطبيق أيفورا ---")
    res7 = send_chat("اسم التطبيق أيفورا", session_id)
    print(f"Reply: {res7['reply']}")
    
    # 8. "ما اسم التطبيق؟"
    print("\n--- Step 8: ما اسم التطبيق؟ ---")
    res8 = send_chat("ما اسم التطبيق؟", session_id)
    print(f"Reply: {res8['reply']}")
    
    print("\n" + "=" * 25 + " CLOSING AND REOPENING APPLICATION (New Session) " + "=" * 25)
    new_session_id = f"session_{uuid.uuid4().hex[:6]}"
    print(f"New Session: {new_session_id}")
    
    # 9. "ما اسمي؟" (from new session)
    print("\n--- Step 9: ما اسمي؟ ---")
    res9 = send_chat("ما اسمي؟", new_session_id)
    print(f"Reply: {res9['reply']}")
    
    # 10. "من أين أنا؟" (from new session)
    print("\n--- Step 10: من أين أنا؟ ---")
    res10 = send_chat("من أين أنا؟", new_session_id)
    print(f"Reply: {res10['reply']}")
    
    # 11. "ما النادي الذي أشجعه؟" (from new session)
    print("\n--- Step 11: ما النادي الذي أشجعه؟ ---")
    res11 = send_chat("ما النادي الذي أشجعه؟", new_session_id)
    print(f"Reply: {res11['reply']}")
    
    print("\n" + "=" * 30 + " TEST SEQUENCE COMPLETED " + "=" * 30)

if __name__ == "__main__":
    run_tests()

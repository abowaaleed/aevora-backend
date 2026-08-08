import sys
import os
import json
import requests
import time

# Add backend to path
sys.path.append(os.path.join(os.getcwd(), 'backend'))

def test_proactive_opening():
    print("\n--- Testing Proactive Opening ---")
    # New session
    session_id = f"test_session_{int(time.time())}"
    res = requests.post(
        "http://127.0.0.1:8000/chat",
        json={
            "message": "hello",
            "skill": "english",
            "session_id": session_id,
            "user_id": "test_user"
        }
    )
    print(f"Status: {res.status_code}")
    reply = res.json().get("reply")
    print(f"Reply: {reply}")

def test_inline_correction_and_persistence():
    print("\n--- Testing Inline Correction & Persistence ---")
    session_id = f"test_session_{int(time.time())}"

    print("User: I goed to the store")
    res = requests.post(
        "http://127.0.0.1:8000/chat",
        json={
            "message": "I goed to the store",
            "skill": "english",
            "session_id": session_id,
            "user_id": "test_user"
        }
    )
    reply = res.json().get("reply")
    print(f"AI: {reply}")

    mistake_file = "backend/data/learning_mistakes.json"
    if os.path.exists(mistake_file):
        with open(mistake_file, "r") as f:
            data = json.load(f)
            user_mistakes = data.get("test_user", [])
            print(f"Recorded mistakes for test_user: {len(user_mistakes)}")
            for m in user_mistakes:
                print(f" - {m['mistake_type']}: {m['example_sentence']} -> {m['corrected_sentence']}")

def test_session_summary():
    print("\n--- Testing Session Summary ---")
    session_id = f"test_session_{int(time.time())}"

    requests.post(
        "http://127.0.0.1:8000/chat",
        json={
            "message": "He don't like pizza",
            "skill": "english",
            "session_id": session_id,
            "user_id": "test_user"
        }
    )

    print("User: goodbye")
    res = requests.post(
        "http://127.0.0.1:8000/chat",
        json={
            "message": "goodbye",
            "skill": "english",
            "session_id": session_id,
            "user_id": "test_user"
        }
    )
    reply = res.json().get("reply")
    print(f"AI: {reply}")

if __name__ == "__main__":
    try:
        test_proactive_opening()
        test_inline_correction_and_persistence()
        test_session_summary()
    except Exception as e:
        print(f"Error: {e}")

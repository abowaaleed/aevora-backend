import requests
import json

base_url = "http://127.0.0.1:8000"

def send_chat(message: str, user_id: str = "default_test_user"):
    payload = {
        "message": message,
        "user_id": user_id,
        "session_id": "test_session_123",
        "skill": "quick"
    }
    response = requests.post(f"{base_url}/chat", json=payload)
    if response.status_code == 200:
        data = response.json()
        print(f"\n========================================")
        print(f"User: {message}")
        print(f"Aevora: {data.get('reply')}")
        runtime = data.get("runtime", {}) or {}
        decision = runtime.get("adaptive_decision", {}) or {}
        print(f"--- Metadata ---")
        print(f"Intent: {decision.get('intent')}")
        print(f"Thinking Mode: {decision.get('thinking_mode')}")
        print(f"Execution Steps: {decision.get('execution_steps')}")
        print(f"Required Tools: {decision.get('required_tools')}")
        print(f"Complexity Score: {decision.get('complexity_score')}")
    else:
        print(f"Error {response.status_code}: {response.text}")

print("Verifying Aevora Live Agent Loop...")
send_chat("كم ٨×٩؟")
send_chat("احفظ أن اسمي صالح.")
send_chat("من أنا؟")
send_chat("ابحث عن آخر أخبار الذكاء الاصطناعي")

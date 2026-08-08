import requests
import json
import uuid

BASE_URL = "http://127.0.0.1:8000"

def send_chat(message: str, session_id: str, skill: str = "quick"):
    payload = {
        "message": message,
        "skill": skill,
        "user_id": "saleh_test",
        "session_id": session_id
    }
    response = requests.post(f"{BASE_URL}/chat", json=payload)
    if response.statusCode == 200 if hasattr(response, "statusCode") else response.status_code == 200:
        return response.json()
    else:
        raise Exception(f"Request failed: {response.text}")

def run_scenarios():
    print("=" * 40 + " STARTING RUNTIME VERIFICATION " + "=" * 40)
    
    # ----------------------------------------------------
    # Scenario 1: Normal conversation
    # ----------------------------------------------------
    print("\n--- Scenario 1: Normal Conversation ---")
    session_1 = f"s1_{uuid.uuid4().hex[:6]}"
    
    msg_1 = "Hello"
    print(f"Input 1: {msg_1}")
    res_1 = send_chat(msg_1, session_1)
    print(f"Reply 1: {res_1['reply']}")
    
    msg_2 = "My name is Saleh"
    print(f"Input 2: {msg_2}")
    res_2 = send_chat(msg_2, session_1)
    print(f"Reply 2: {res_2['reply']}")
    
    msg_3 = "What is my name?"
    print(f"Input 3: {msg_3}")
    res_3 = send_chat(msg_3, session_1)
    print(f"Reply 3: {res_3['reply']}")
    print(f"Runtime Metadata: {json.dumps(res_3.get('runtime', {}), ensure_ascii=False, indent=2)}")

    # ----------------------------------------------------
    # Scenario 2: Long term memory
    # ----------------------------------------------------
    print("\n--- Scenario 2: Long Term Memory ---")
    session_2a = f"s2a_{uuid.uuid4().hex[:6]}"
    session_2b = f"s2b_{uuid.uuid4().hex[:6]}"
    
    msg_2_save = "My favourite club is Al Hilal."
    print(f"Input (Session A): {msg_2_save}")
    res_2_save = send_chat(msg_2_save, session_2a)
    print(f"Reply (Session A): {res_2_save['reply']}")
    
    msg_2_ask = "What club do I support?"
    print(f"Input (New Session B): {msg_2_ask}")
    res_2_ask = send_chat(msg_2_ask, session_2b)
    print(f"Reply (New Session B): {res_2_ask['reply']}")
    print(f"Runtime Metadata: {json.dumps(res_2_ask.get('runtime', {}), ensure_ascii=False, indent=2)}")

    # ----------------------------------------------------
    # Scenario 3: Conversation overrides memory
    # ----------------------------------------------------
    print("\n--- Scenario 3: Conversation Overrides Memory ---")
    session_3 = f"s3_{uuid.uuid4().hex[:6]}"
    
    # Pre-populate memory for user "saleh_test" in session_3 (already saved Hilal)
    msg_3_1 = "Actually I now support Al Nassr."
    print(f"Input 1: {msg_3_1}")
    res_3_1 = send_chat(msg_3_1, session_3)
    print(f"Reply 1: {res_3_1['reply']}")
    
    msg_3_2 = "Which club do I support?"
    print(f"Input 2: {msg_3_2}")
    res_3_2 = send_chat(msg_3_2, session_3)
    print(f"Reply 2: {res_3_2['reply']}")
    print(f"Runtime Metadata: {json.dumps(res_3_2.get('runtime', {}), ensure_ascii=False, indent=2)}")

    # ----------------------------------------------------
    # Scenario 4: Planner
    # ----------------------------------------------------
    print("\n--- Scenario 4: Planner ---")
    session_4 = f"s4_{uuid.uuid4().hex[:6]}"
    msg_4 = "Plan a five-day trip to Istanbul."
    print(f"Input: {msg_4}")
    res_4 = send_chat(msg_4, session_4, skill="travel")
    print(f"Reply: {res_4['reply']}")
    print(f"Runtime Metadata: {json.dumps(res_4.get('runtime', {}), ensure_ascii=False, indent=2)}")

    # ----------------------------------------------------
    # Scenario 5: Calculator
    # ----------------------------------------------------
    print("\n--- Scenario 5: Calculator ---")
    session_5 = f"s5_{uuid.uuid4().hex[:6]}"
    msg_5 = "17 × 91"
    print(f"Input: {msg_5}")
    res_5 = send_chat(msg_5, session_5)
    print(f"Reply: {res_5['reply']}")
    print(f"Runtime Metadata: {json.dumps(res_5.get('runtime', {}), ensure_ascii=False, indent=2)}")

    # ----------------------------------------------------
    # Scenario 6: Weather
    # ----------------------------------------------------
    print("\n--- Scenario 6: Weather ---")
    session_6 = f"s6_{uuid.uuid4().hex[:6]}"
    msg_6 = "How is the weather tomorrow in Riyadh?"
    print(f"Input: {msg_6}")
    res_6 = send_chat(msg_6, session_6)
    print(f"Reply: {res_6['reply']}")
    print(f"Runtime Metadata: {json.dumps(res_6.get('runtime', {}), ensure_ascii=False, indent=2)}")

    # ----------------------------------------------------
    # Scenario 7: Voice
    # ----------------------------------------------------
    print("\n--- Scenario 7: Voice ---")
    session_7 = f"s7_{uuid.uuid4().hex[:6]}"
    
    # 1. Simulate speech transcription "My name is Saleh."
    print("Speech STT -> My name is Saleh.")
    res_7_1 = send_chat("My name is Saleh.", session_7)
    print(f"Reply 1: {res_7_1['reply']}")
    
    # 2. Ask by voice
    print("Speech STT -> What is my name?")
    res_7_2 = send_chat("What is my name?", session_7)
    print(f"Reply 2: {res_7_2['reply']}")
    print(f"Runtime Metadata: {json.dumps(res_7_2.get('runtime', {}), ensure_ascii=False, indent=2)}")

    # ----------------------------------------------------
    # Scenario 8: Mixed Language
    # ----------------------------------------------------
    print("\n--- Scenario 8: Mixed Language ---")
    session_8 = f"s8_{uuid.uuid4().hex[:6]}"
    
    lang_msgs = [
        "What is your name?",
        "ما اسمك؟",
        "How are you today?",
        "كيف حالك اليوم؟"
    ]
    for m in lang_msgs:
        print(f"Input: {m}")
        res_l = send_chat(m, session_8)
        print(f"Reply: {res_l['reply']}")

    print("\n" + "=" * 40 + " VERIFICATION COMPLETE " + "=" * 40)

if __name__ == "__main__":
    run_scenarios()

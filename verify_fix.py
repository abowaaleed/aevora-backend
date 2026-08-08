import requests
import json
import time

def test_chat():
    print("Testing Chat Pipeline with reported quality issue...")
    url = "http://127.0.0.1:8000/chat"
    payload = {
        "message": "تكلم معي باللغة الانجليزية فقط. الان قل لي ما هو طعامك المفضل ثم بعدها اسألني ما هي عاصمة السعودية، كلها بالانجليزية.",
        "skill": "quick"
    }
    start = time.time()
    try:
        response = requests.post(url, json=payload, timeout=120)
        end = time.time()
        print(f"Status Code: {response.status_code}")
        data = response.json()
        print(f"Reply: {data['reply']}")
        print(f"Skill Used: {data['skill_used']}")
        print(f"Adaptive Decision: {json.dumps(data['runtime']['adaptive_decision'], indent=2, ensure_ascii=False)}")
        print(f"Time Taken: {end - start:.2f}s")
        return data
    except Exception as e:
        print(f"Error: {e}")
        return None

def test_transcribe():
    print("\nTesting Transcription Pipeline...")
    url = "http://127.0.0.1:8000/voice/transcribe"
    files = {'file': ('test.wav', open('/Users/sw411/Documents/AIProjects/EnglishCompanion/arabic_sample_3.wav', 'rb'), 'audio/wav')}
    start = time.time()
    try:
        response = requests.post(url, files=files, timeout=60)
        end = time.time()
        print(f"Status Code: {response.status_code}")
        data = response.json()
        print(f"Transcribed Text: '{data['text']}'")
        print(f"Time Taken: {end - start:.2f}s")
        return data
    except Exception as e:
        print(f"Error: {e}")
        return None

if __name__ == "__main__":
    test_chat()
    test_transcribe()

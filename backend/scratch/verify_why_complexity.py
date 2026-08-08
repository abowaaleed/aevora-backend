import sys
from pathlib import Path

# Add project root to path
sys.path.append(str(Path(__file__).parent.parent))

from app.adaptive.adaptive_engine import AdaptiveEngine

def verify_why():
    engine = AdaptiveEngine()

    test_cases = [
        "why is the sky blue",
        "ليش السماء زرقاء",
        "why does it rain",
        "لماذا تسقط الأمطار",
        "why doesn't a male lion give birth",
        "لماذا لا تلد الأسود الذكور",
        "why should I learn English with Aevora"
    ]

    print(f"{'Query':<45} | {'Tier':<10} | {'Score':<10} | {'Intent':<12}")
    print("-" * 85)
    for query in test_cases:
        decision = engine.analyze(query)
        print(f"{query[:45]:<45} | {decision.tier:<10} | {decision.complexity_score:<10.2f} | {decision.intent:<12}")

if __name__ == "__main__":
    verify_why()

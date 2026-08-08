import re

TRIVIAL_PATTERNS = [
    r"مرحبا", r"اهلين", r"أهلاً", r"اهلا", r"السلام عليكم", r"مرحبًا", 
    r"صباح الخير", r"مساء الخير", r"كيفك", r"كيف الحال",
    r"hello", r"hi", r"hey", r"greetings", r"good morning", r"good evening", r"how are you"
]

def is_trivial_input(text: str) -> bool:
    """
    Deterministic rule-based check to identify simple greetings and small talk.
    Runs in under 1ms, requiring no LLM calls.
    """
    if not text:
        return True
        
    cleaned = text.strip().lower()
    
    # Exclusion keywords (requests that ask for plans, lists, itineraries, explanations, or require multi-part output)
    exclusion_keywords = [
        "خطة", "برنامج", "أيام", "ايام", "قائمة", "اشرح", "فصّل", "فصل", 
        "plan", "program", "days", "list", "explain", "detail"
    ]
    if any(kw in cleaned for kw in exclusion_keywords):
        return False
    
    # 1. Length constraint (trivial turns are typically very short)
    if len(cleaned) > 20:
        return False
        
    # 2. No questions
    if "?" in cleaned or "؟" in cleaned:
        return False
        
    # 3. No numbers
    if any(char.isdigit() for char in cleaned):
        return False
        
    # 4. Matches known greeting patterns
    for pattern in TRIVIAL_PATTERNS:
        if re.search(r"\b" + pattern + r"\b", cleaned, re.IGNORECASE) or pattern in cleaned:
            return True
            
    # Fallback to length-only heuristic for extremely short utterances (e.g. "ok", "yes", "نعم")
    if len(cleaned) < 5:
        return True
        
    return False

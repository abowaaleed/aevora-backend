"""
Intent detector for the Adaptive Intelligence Engine.

This module uses deterministic rules to detect user intent from the message.
No AI is used - only pattern matching and keyword analysis.
"""

from .types import IntentType


class IntentDetector:
    """Detects user intent using deterministic rules."""
    
    def __init__(self):
        """Initialize the intent detector with keyword patterns."""
        self.learning_keywords = [
            "learn", "teach", "explain", "what is", "how do", "translate",
            "define", "meaning", "understand", "help me understand",
            "tutorial", "lesson", "study", "practice", "grammar",
            "درس", "تعلم", "تعليم", "قواعد", "إنجليزي", "لغة", "شرح",
            "كيف اقول", "معنى كلمة", "ترجم", "ترجمة", "شرح"
        ]
        
        self.programming_keywords = [
            "code", "programming", "function", "class", "debug", "error",
            "api", "database", "algorithm", "data structure", "framework",
            "library", "build", "deploy", "test", "refactor", "git",
            "python", "javascript", "java", "rust", "go", "flutter", "react",
            "angular", "vue", "node", "sql", "nosql", "docker", "kubernetes",
            "برمجة", "كود", "خوارزمية", "قاعدة بيانات", "تطوير"
        ]
        
        self.research_keywords = [
            "research", "find", "search", "information about", "tell me about",
            "history of", "who is", "when was", "where is", "statistics",
            "data", "analysis", "compare", "versus", "vs", "difference between",
            "why", "how come", "reason for",
            "ابحث", "البحث", "بحث", "معلومات", "تاريخ", "من هو", "أين يقع", "اين يقع", "ما هو", "ما هي", "لماذا", "كيف"
        ]
        
        self.decision_keywords = [
            "should i", "what should", "help me decide", "choose between",
            "recommend", "advice", "opinion", "what do you think", "better",
            "pros and cons", "advantages", "disadvantages", "evaluate",
            "هل يجب", "ماذا يجب", "ساعدني في الاختيار", "انصحني", "نصيحة", "رأيك", "أيهما أفضل", "ايهما افضل", "مميزات وعيوب"
        ]
        
        self.travel_keywords = [
            "travel", "trip", "vacation", "visit", "flight", "hotel",
            "destination", "country", "city", "tourist", "attraction",
            "restaurant", "weather", "visa", "passport", "itinerary",
            "برنامج سياحي", "خطة سفر", "رحلة", "جولة سياحية", "أماكن سياحية", "حجز فندق", "طيران", "سفر", "سياحة", "سياحي"
        ]
        
        self.conversation_keywords = [
            "hello", "hi", "hey", "how are you", "good morning", "good evening",
            "good night", "thanks", "thank you", "bye", "goodbye", "see you",
            "how's it going", "what's up", "nice to meet", "feeling", "mood",
            "أهلاً", "مرحباً", "كيف حالك", "شكراً", "وداعاً", "صباح الخير", "مساء الخير"
        ]
    
    def detect(self, message: str) -> IntentType:
        """
        Detect the intent from the user message.
        
        Args:
            message: The user's message
            
        Returns:
            The detected intent type
        """
        message_lower = message.lower()
        
        # Check each intent category
        if self._matches_keywords(message_lower, self.programming_keywords):
            return IntentType.PROGRAMMING
        
        if self._matches_keywords(message_lower, self.learning_keywords):
            return IntentType.LEARNING
        
        if self._matches_keywords(message_lower, self.research_keywords):
            return IntentType.RESEARCH
        
        if self._matches_keywords(message_lower, self.decision_keywords):
            return IntentType.DECISION
        
        if self._matches_keywords(message_lower, self.travel_keywords):
            return IntentType.TRAVEL
        
        if self._matches_keywords(message_lower, self.conversation_keywords):
            return IntentType.CONVERSATION
        
        # Default to general if no specific intent detected
        return IntentType.GENERAL
    
    def _matches_keywords(self, message: str, keywords: list[str]) -> bool:
        """
        Check if the message contains any of the keywords.
        
        Args:
            message: The lowercased message
            keywords: List of keywords to check
            
        Returns:
            True if any keyword is found in the message
        """
        for keyword in keywords:
            if keyword in message:
                return True
        return False

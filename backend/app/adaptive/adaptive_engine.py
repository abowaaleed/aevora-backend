"""
Adaptive Intelligence Engine.

This module provides the main AdaptiveEngine class that analyzes user requests
to determine intent, complexity, response style, thinking mode, and other
adaptive parameters using deterministic rules (no AI).
"""

from typing import Optional
from .types import AdaptiveDecision, IntentType
from .intent_detector import IntentDetector
from .response_style import ResponseStyleAnalyzer
from .thinking_mode import ThinkingModeAnalyzer


class AdaptiveEngine:
    """
    Adaptive Intelligence Engine for request analysis.
    
    This engine analyzes user requests using deterministic rules to determine
    the optimal processing parameters without using AI. It provides a single
    public method `analyze()` that returns an AdaptiveDecision.
    """
    
    def __init__(self):
        """Initialize the adaptive engine with its analyzers."""
        self.intent_detector = IntentDetector()
        self.response_style_analyzer = ResponseStyleAnalyzer()
        self.thinking_mode_analyzer = ThinkingModeAnalyzer()
    
    def analyze(self, user_message: str, mode: Optional[str] = None) -> AdaptiveDecision:
        """
        Analyze a user message and return adaptive decision.
        """
        # Detect intent
        intent = self.intent_detector.detect(user_message)

        # Override intent if mode is provided
        if mode == "pdf":
            intent = IntentType.RESEARCH
            print("[ADAPTIVE ENGINE] Overriding intent to RESEARCH for PDF mode.")

        # Determine thinking mode
        thinking_mode = self.thinking_mode_analyzer.determine(user_message, intent)
        
        # Determine response style
        response_style = self.response_style_analyzer.determine(user_message, intent)
        
        # Determine if memory is needed
        need_memory = self._determine_memory_need(user_message, intent)
        
        # Determine if plugins are needed
        need_plugins = self._determine_plugin_need(user_message, intent)
        
        # Calculate complexity score
        complexity_score = self._calculate_complexity(user_message, intent)

        # Determine complexity tier
        if complexity_score < 0.3:
            tier = "low"
        elif complexity_score < 0.5:
            tier = "medium"
        else:
            tier = "high"

        # Calculate confidence
        confidence = self._calculate_confidence(user_message, intent)
        
        # Determine required tools
        required_tools = []
        message_lower = user_message.lower()
        if any(p in message_lower for p in ["calculate", "compute", "vat", "+", "*", "/", "×", "÷", "احسب", "كم"]):
            required_tools.append("calculator")
        if any(p in message_lower for p in ["weather", "temperature", "forecast", "rain", "الطقس", "طقس", "حرارة", "درجة الحرارة"]):
            required_tools.append("weather")
        if any(p in message_lower for p in ["search", "news", "current", "latest", "elon musk", "who is", "what is", "ابحث", "البحث", "بحث"]):
            if not any(p in message_lower for p in ["weather", "calculate", "+", "*", "/", "×", "÷", "الطقس", "طقس", "احسب", "كم"]):
                required_tools.append("web_search")
        if any(p in message_lower for p in ["من أنا", "ما اسمي", "من اكون", "who am i", "my name"]):
            required_tools.append("user_brain")

        # Determine execution steps
        if "user_brain" in required_tools:
            execution_steps = [
                "Load User Brain profile context",
                "Format identity preferences",
                "Construct personal greeting"
            ]
        elif any(p in message_lower for p in ["احفظ أن", "تذكر أن", "save that", "remember that"]):
            execution_steps = [
                "Extract memory content statement",
                "Call Memory Engine store save",
                "Confirm storage to user"
            ]
        elif intent == IntentType.TRAVEL:
            execution_steps = [
                "Identify destination preferences",
                "Formulate travel budget bounds",
                "Check duration constraints",
                "Verify visa/passport requirements",
                "Propose initial itinerary draft"
            ]
        elif "calculator" in required_tools:
            execution_steps = [
                "Match arithmetic expression in query",
                "Execute calculator tool internally",
                "Evaluate formula result safely",
                "Format mathematical answer"
            ]
        elif "weather" in required_tools:
            execution_steps = [
                "Detect city/location from message",
                "Fetch forecast data from Weather API",
                "Compare daily weather metrics",
                "Structure forecast summary"
            ]
        elif "web_search" in required_tools:
            execution_steps = [
                "Extract search query terms",
                "Run search engine request",
                "Parse snippet results",
                "Synthesize findings into response"
            ]
        else:
            # General conversation planning steps
            execution_steps = [
                "Identify query intent",
                "Retrieve recent conversation context",
                "Evaluate user tone preference",
                "Formulate conversational response"
            ]

        return AdaptiveDecision(
            intent=intent,
            thinking_mode=thinking_mode,
            response_style=response_style,
            need_memory=need_memory,
            need_plugins=need_plugins,
            complexity_score=complexity_score,
            tier=tier,
            confidence=confidence,
            required_tools=required_tools,
            execution_steps=execution_steps
        )
    
    def _determine_memory_need(self, message: str, intent: IntentType) -> bool:
        """
        Determine if memory retrieval is needed.
        
        Args:
            message: The user's message
            intent: The detected intent
            
        Returns:
            True if memory is needed, False otherwise
        """
        message_lower = message.lower()
        
        # Memory needed for personal references
        memory_patterns = [
            "remember", "my", "i previously", "we discussed", "last time",
            "as i mentioned", "earlier", "before", "again", "continue",
            "احفظ", "تذكر", "اسمي", "من أنا", "من انا", "اسم", "نادي", "شجع", "أين", "اين", "أعيش", "اعيش", "مدينة", "تطبيق"
        ]
        
        for pattern in memory_patterns:
            if pattern in message_lower:
                return True
        
        # Intent-based memory needs
        memory_intents = [IntentType.DECISION]
        if intent in memory_intents:
            return True
        
        return False
    
    def _determine_plugin_need(self, message: str, intent: IntentType) -> bool:
        """
        Determine if plugin execution is needed.
        
        Args:
            message: The user's message
            intent: The detected intent
            
        Returns:
            True if plugins are needed, False otherwise
        """
        message_lower = message.lower()
        
        # Plugin needed for specific actions
        plugin_patterns = [
            "calculate", "compute", "search", "look up", "find current",
            "weather", "news", "stock", "price", "convert", "translate",
            "احسب", "كم", "طقس", "الطقس", "ابحث", "بحث", "+", "-", "*", "/", "×", "÷"
        ]
        
        for pattern in plugin_patterns:
            if pattern in message_lower:
                return True
        
        # Intent-based plugin needs
        plugin_intents = [IntentType.RESEARCH, IntentType.TRAVEL]
        if intent in plugin_intents:
            return True
        
        return False
    
    def _calculate_complexity(self, message: str, intent: IntentType) -> float:
        """
        Calculate complexity score from 0.0 to 1.0.
        
        Args:
            message: The user's message
            intent: The detected intent
            
        Returns:
            Complexity score between 0.0 and 1.0
        """
        word_count = len(message.split())
        sentence_count = message.count('.') + message.count('!') + message.count('?')
        
        # Base complexity from word count
        if word_count <= 5:
            word_complexity = 0.1
        elif word_count <= 10:
            word_complexity = 0.3
        elif word_count <= 20:
            word_complexity = 0.5
        elif word_count <= 40:
            word_complexity = 0.7
        else:
            word_complexity = 0.9
        
        # Adjust for sentence count (more sentences = more complex)
        if sentence_count >= 3:
            word_complexity = min(1.0, word_complexity + 0.1)
        
        # Intent-based complexity adjustment
        intent_complexity_map = {
            IntentType.PROGRAMMING: 0.8,
            IntentType.LEARNING: 0.7,
            IntentType.RESEARCH: 0.7,
            IntentType.DECISION: 0.6,
            IntentType.TRAVEL: 0.5,
            IntentType.CONVERSATION: 0.2,
            IntentType.GENERAL: 0.4
        }
        
        intent_complexity = intent_complexity_map.get(intent, 0.5)
        
        # Average word and intent complexity
        return (word_complexity + intent_complexity) / 2
    
    def _calculate_confidence(self, message: str, intent: IntentType) -> float:
        """
        Calculate confidence in the analysis from 0.0 to 1.0.
        
        Args:
            message: The user's message
            intent: The detected intent
            
        Returns:
            Confidence score between 0.0 and 1.0
        """
        # High confidence for clear intents
        clear_intents = [IntentType.PROGRAMMING, IntentType.LEARNING, IntentType.TRAVEL]
        if intent in clear_intents:
            return 0.9
        
        # Medium confidence for conversation and general
        medium_intents = [IntentType.CONVERSATION, IntentType.GENERAL]
        if intent in medium_intents:
            return 0.7
        
        # Lower confidence for ambiguous intents
        ambiguous_intents = [IntentType.RESEARCH, IntentType.DECISION]
        if intent in ambiguous_intents:
            return 0.6
        
        # Default confidence
        return 0.7

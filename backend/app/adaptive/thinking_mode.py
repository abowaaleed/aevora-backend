"""
Thinking mode analyzer for the Adaptive Intelligence Engine.

This module uses deterministic rules to determine the appropriate
thinking depth based on the message characteristics.
"""

import re
from .types import ThinkingMode, IntentType


class ThinkingModeAnalyzer:
    """Determines thinking mode using deterministic rules."""
    
    def determine(self, message: str, intent: IntentType) -> ThinkingMode:
        """
        Determine the appropriate thinking mode.
        
        Args:
            message: The user's message
            intent: The detected intent
            
        Returns:
            The appropriate thinking mode
        """
        message_lower = message.lower()
        word_count = len(message.split())
        
        # Helper to match whole words/phrases using word boundaries
        def has_pattern(pattern: str) -> bool:
            return bool(re.search(rf"\b{re.escape(pattern)}\b", message_lower))

        # Fast for greetings
        greeting_patterns = [
            "hello", "hi", "hey", "thanks", "thank you", "bye", "goodbye",
            "good morning", "good evening", "good night"
        ]
        for pattern in greeting_patterns:
            if has_pattern(pattern):
                return ThinkingMode.FAST

        # Fast mode for very short, simple queries (unless GENERAL intent, which defaults to NORMAL)
        if word_count <= 3 and intent != IntentType.GENERAL:
            return ThinkingMode.FAST
        
        # Fast for quick factual questions
        fast_patterns = [
            "what is", "who is", "when is", "where is", "how many",
            "what time", "what date", "is it", "does it", "can it",
            "translate", "define", "meaning of"
        ]
        for pattern in fast_patterns:
            if has_pattern(pattern):
                return ThinkingMode.FAST
        
        # Deep mode for complex requests
        deep_patterns = [
            "explain in detail", "tell me more about", "comprehensive",
            "thorough", "deep dive", "extensive", "elaborate",
            "step by step", "walk through", "guide me", "analyze",
            "evaluate", "assess", "critique", "compare in detail"
        ]
        for pattern in deep_patterns:
            if has_pattern(pattern):
                return ThinkingMode.DEEP
        
        # Deep mode for complex questions
        if "why" in message_lower and word_count > 10:
            return ThinkingMode.DEEP
        
        if "how" in message_lower and word_count > 10:
            return ThinkingMode.DEEP
        
        # Intent-based defaults
        intent_mode_map = {
            IntentType.PROGRAMMING: ThinkingMode.DEEP,
            IntentType.LEARNING: ThinkingMode.DEEP,
            IntentType.RESEARCH: ThinkingMode.DEEP,
            IntentType.DECISION: ThinkingMode.DEEP,
            IntentType.TRAVEL: ThinkingMode.NORMAL,
            IntentType.CONVERSATION: ThinkingMode.FAST,
            IntentType.GENERAL: ThinkingMode.NORMAL
        }
        
        return intent_mode_map.get(intent, ThinkingMode.NORMAL)

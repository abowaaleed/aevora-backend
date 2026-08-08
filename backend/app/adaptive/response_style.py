"""
Response style analyzer for the Adaptive Intelligence Engine.

This module uses deterministic rules to determine the appropriate
response length based on the message characteristics.
"""

import re
from .types import ResponseStyle, IntentType


class ResponseStyleAnalyzer:
    """Determines response style using deterministic rules."""
    
    def determine(self, message: str, intent: IntentType) -> ResponseStyle:
        """
        Determine the appropriate response style.
        
        Args:
            message: The user's message
            intent: The detected intent
            
        Returns:
            The appropriate response style
        """
        message_lower = message.lower()
        word_count = len(message.split())
        
        # Helper to match whole words/phrases using word boundaries
        def has_pattern(pattern: str) -> bool:
            return bool(re.search(rf"\b{re.escape(pattern)}\b", message_lower))

        # Short for greetings and simple interactions (checked first, excluding 'hi')
        short_patterns = [
            "hello", "hey", "thanks", "thank you", "bye", "goodbye",
            "good morning", "good evening", "good night"
        ]
        for pattern in short_patterns:
            if has_pattern(pattern):
                return ResponseStyle.SHORT

        # Ultra short responses for very short, simple queries
        if word_count <= 3:
            return ResponseStyle.ULTRA_SHORT
        
        # Ultra short for simple factual questions
        ultra_short_patterns = [
            "what is", "who is", "when is", "where is", "how many",
            "what time", "what date", "is it", "does it", "can it"
        ]
        for pattern in ultra_short_patterns:
            if has_pattern(pattern):
                return ResponseStyle.ULTRA_SHORT
        
        # Long responses for complex requests (if explicitly requested)
        long_patterns = [
            "explain in detail", "tell me more about", "comprehensive",
            "thorough", "deep dive", "extensive", "elaborate",
            "step by step", "walk through", "guide me"
        ]
        for pattern in long_patterns:
            if has_pattern(pattern):
                return ResponseStyle.LONG

        # Intent-based defaults for complex tasks
        complex_intents = [IntentType.PROGRAMMING, IntentType.LEARNING, IntentType.RESEARCH]
        if intent in complex_intents:
            return ResponseStyle.LONG
            
        # Short responses for quick questions (for non-complex intents, excluding decision/travel/general)
        if word_count <= 10 and intent not in [IntentType.DECISION, IntentType.TRAVEL, IntentType.GENERAL]:
            return ResponseStyle.SHORT
        
        # Intent-based defaults
        intent_style_map = {
            IntentType.DECISION: ResponseStyle.MEDIUM,
            IntentType.TRAVEL: ResponseStyle.MEDIUM,
            IntentType.CONVERSATION: ResponseStyle.SHORT,
            IntentType.GENERAL: ResponseStyle.MEDIUM
        }
        
        return intent_style_map.get(intent, ResponseStyle.MEDIUM)

"""
Unit tests for Adaptive Engine.
"""

import pytest
from app.adaptive import AdaptiveEngine, IntentType, ResponseStyle, ThinkingMode


class TestAdaptiveEngine:
    """Test cases for AdaptiveEngine."""
    
    def test_analyze_translate_request(self, adaptive_engine):
        """Test analysis of a translation request."""
        result = adaptive_engine.analyze("Translate this")
        
        assert result.intent == IntentType.LEARNING
        assert result.thinking_mode == ThinkingMode.FAST
        assert result.response_style == ResponseStyle.ULTRA_SHORT
        assert 0.0 <= result.complexity_score <= 1.0
        assert 0.0 <= result.confidence <= 1.0
    
    def test_analyze_programming_request(self, adaptive_engine):
        """Test analysis of a programming request."""
        result = adaptive_engine.analyze("I want to build Flutter app")
        
        assert result.intent == IntentType.PROGRAMMING
        assert result.thinking_mode == ThinkingMode.DEEP
        assert result.response_style == ResponseStyle.LONG
    
    def test_analyze_decision_request(self, adaptive_engine):
        """Test analysis of a decision request."""
        result = adaptive_engine.analyze("What do you think")
        
        assert result.intent == IntentType.DECISION
        assert result.thinking_mode == ThinkingMode.DEEP
        assert result.response_style == ResponseStyle.MEDIUM
    
    def test_analyze_conversation_request(self, adaptive_engine):
        """Test analysis of a conversation request."""
        result = adaptive_engine.analyze("Hello")
        
        assert result.intent == IntentType.CONVERSATION
        assert result.thinking_mode == ThinkingMode.FAST
        assert result.response_style == ResponseStyle.SHORT
    
    def test_analyze_travel_request(self, adaptive_engine):
        """Test analysis of a travel request."""
        result = adaptive_engine.analyze("I want to travel to Paris")
        
        assert result.intent == IntentType.TRAVEL
        assert result.thinking_mode == ThinkingMode.NORMAL
        assert result.response_style == ResponseStyle.MEDIUM
    
    def test_analyze_research_request(self, adaptive_engine):
        """Test analysis of a research request."""
        result = adaptive_engine.analyze("Tell me about the history of Rome")
        
        assert result.intent == IntentType.RESEARCH
        assert result.thinking_mode == ThinkingMode.DEEP
        assert result.response_style == ResponseStyle.LONG
    
    def test_memory_need_detection(self, adaptive_engine):
        """Test memory need detection."""
        result = adaptive_engine.analyze("Remember what we discussed")
        assert result.need_memory is True
        
        result = adaptive_engine.analyze("Hello")
        assert result.need_memory is False
    
    def test_plugin_need_detection(self, adaptive_engine):
        """Test plugin need detection."""
        result = adaptive_engine.analyze("Calculate 2 + 2")
        assert result.need_plugins is True
        
        result = adaptive_engine.analyze("Hello")
        assert result.need_plugins is False
    
    def test_complexity_score_range(self, adaptive_engine):
        """Test complexity score is always in valid range."""
        messages = [
            "Hi",
            "Hello, how are you?",
            "Can you help me understand how to build a Flutter application with proper architecture and state management?",
            "I need a comprehensive guide on machine learning algorithms including supervised, unsupervised, and reinforcement learning with practical examples."
        ]
        
        for message in messages:
            result = adaptive_engine.analyze(message)
            assert 0.0 <= result.complexity_score <= 1.0
    
    def test_confidence_score_range(self, adaptive_engine):
        """Test confidence score is always in valid range."""
        messages = ["Hello", "Write Python code", "What is the weather?"]
        
        for message in messages:
            result = adaptive_engine.analyze(message)
            assert 0.0 <= result.confidence <= 1.0

    def test_planning_tool_and_steps_calculator(self, adaptive_engine):
        """Test planning outputs for calculator tools."""
        result = adaptive_engine.analyze("Calculate 5 * 5")
        assert "calculator" in result.required_tools
        assert len(result.execution_steps) > 0
        assert "arithmetic" in result.execution_steps[0]

        # Arabic test
        result_ar = adaptive_engine.analyze("كم ٨×٩؟")
        assert "calculator" in result_ar.required_tools

    def test_planning_tool_and_steps_weather(self, adaptive_engine):
        """Test planning outputs for weather tools."""
        result = adaptive_engine.analyze("What is the weather tomorrow?")
        assert "weather" in result.required_tools
        assert len(result.execution_steps) > 0
        assert "weather" in result.execution_steps[1].lower()

        # Arabic test
        result_ar = adaptive_engine.analyze("ما هو طقس الرياض؟")
        assert "weather" in result_ar.required_tools

    def test_planning_tool_and_steps_web_search(self, adaptive_engine):
        """Test planning outputs for web search tools."""
        result = adaptive_engine.analyze("Who is Elon Musk?")
        assert "web_search" in result.required_tools
        assert len(result.execution_steps) > 0

        # Arabic test
        result_ar = adaptive_engine.analyze("ابحث عن آخر أخبار الذكاء الاصطناعي")
        assert "web_search" in result_ar.required_tools

    def test_planning_tool_and_steps_brain_and_memory(self, adaptive_engine):
        """Test planning outputs for brain and memory triggers."""
        result_brain = adaptive_engine.analyze("من أنا؟")
        assert "user_brain" in result_brain.required_tools
        assert "User Brain" in result_brain.execution_steps[0]

        result_mem = adaptive_engine.analyze("تذكر أن اسمي صالح")
        assert len(result_mem.execution_steps) > 0
        assert "Memory Engine" in result_mem.execution_steps[1]


class TestIntentDetector:
    """Test cases for IntentDetector."""
    
    def test_programming_keywords(self, adaptive_engine):
        """Test programming intent detection."""
        assert adaptive_engine.intent_detector.detect("Write Python code") == IntentType.PROGRAMMING
        assert adaptive_engine.intent_detector.detect("Debug this function") == IntentType.PROGRAMMING
        assert adaptive_engine.intent_detector.detect("Build a React app") == IntentType.PROGRAMMING
    
    def test_learning_keywords(self, adaptive_engine):
        """Test learning intent detection."""
        assert adaptive_engine.intent_detector.detect("Teach me Spanish") == IntentType.LEARNING
        assert adaptive_engine.intent_detector.detect("Explain quantum physics") == IntentType.LEARNING
        assert adaptive_engine.intent_detector.detect("What is machine learning?") == IntentType.LEARNING
    
    def test_research_keywords(self, adaptive_engine):
        """Test research intent detection."""
        assert adaptive_engine.intent_detector.detect("Research this topic") == IntentType.RESEARCH
        assert adaptive_engine.intent_detector.detect("Find information about") == IntentType.RESEARCH
        assert adaptive_engine.intent_detector.detect("Tell me about the history") == IntentType.RESEARCH


class TestResponseStyleAnalyzer:
    """Test cases for ResponseStyleAnalyzer."""
    
    def test_ultra_short_detection(self, adaptive_engine):
        """Test ultra short response style detection."""
        assert adaptive_engine.response_style_analyzer.determine("Hi", IntentType.CONVERSATION) == ResponseStyle.ULTRA_SHORT
        assert adaptive_engine.response_style_analyzer.determine("What time is it", IntentType.GENERAL) == ResponseStyle.ULTRA_SHORT
    
    def test_short_detection(self, adaptive_engine):
        """Test short response style detection."""
        assert adaptive_engine.response_style_analyzer.determine("Hello, how are you?", IntentType.CONVERSATION) == ResponseStyle.SHORT
    
    def test_long_detection(self, adaptive_engine):
        """Test long response style detection."""
        message = "Explain in detail how to build a complete application"
        assert adaptive_engine.response_style_analyzer.determine(message, IntentType.PROGRAMMING) == ResponseStyle.LONG


class TestThinkingModeAnalyzer:
    """Test cases for ThinkingModeAnalyzer."""
    
    def test_fast_mode_detection(self, adaptive_engine):
        """Test fast thinking mode detection."""
        assert adaptive_engine.thinking_mode_analyzer.determine("Hi", IntentType.CONVERSATION) == ThinkingMode.FAST
        assert adaptive_engine.thinking_mode_analyzer.determine("What is", IntentType.GENERAL) == ThinkingMode.FAST
    
    def test_deep_mode_detection(self, adaptive_engine):
        """Test deep thinking mode detection."""
        message = "Explain in detail the architecture of microservices"
        assert adaptive_engine.thinking_mode_analyzer.determine(message, IntentType.PROGRAMMING) == ThinkingMode.DEEP
    
    def test_normal_mode_detection(self, adaptive_engine):
        """Test normal thinking mode detection."""
        assert adaptive_engine.thinking_mode_analyzer.determine("How are you?", IntentType.GENERAL) == ThinkingMode.NORMAL

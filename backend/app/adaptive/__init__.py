"""
Adaptive Intelligence Engine package.

This package provides adaptive request analysis using deterministic rules
(no AI). It analyzes user messages to determine intent, complexity,
response style, thinking mode, and other adaptive parameters.
"""

from .types import IntentType, ResponseStyle, ThinkingMode, AdaptiveDecision
from .intent_detector import IntentDetector
from .response_style import ResponseStyleAnalyzer
from .thinking_mode import ThinkingModeAnalyzer
from .adaptive_engine import AdaptiveEngine

__all__ = [
    "IntentType",
    "ResponseStyle",
    "ThinkingMode",
    "AdaptiveDecision",
    "IntentDetector",
    "ResponseStyleAnalyzer",
    "ThinkingModeAnalyzer",
    "AdaptiveEngine",
]

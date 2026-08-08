"""
English Learning Engine package.

This package provides English learning capabilities using deterministic rules
(no AI). It includes grammar checking, lesson building, exercise generation,
progress tracking, and feedback formatting.
"""

from .english_models import GrammarTopic, GrammarMistake, Lesson, Exercise, EnglishResult
from .grammar_checker import GrammarChecker
from .lesson_builder import LessonBuilder
from .exercise_builder import ExerciseBuilder
from .progress_tracker import ProgressTracker
from .feedback_builder import FeedbackBuilder
from .english_engine import EnglishEngine

__all__ = [
    "GrammarTopic",
    "GrammarMistake",
    "Lesson",
    "Exercise",
    "EnglishResult",
    "GrammarChecker",
    "LessonBuilder",
    "ExerciseBuilder",
    "ProgressTracker",
    "FeedbackBuilder",
    "EnglishEngine",
]

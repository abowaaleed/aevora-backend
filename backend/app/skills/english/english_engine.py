"""
English Learning Engine.

This module provides the main EnglishEngine class that processes English learning
requests using deterministic rules (no AI). It coordinates grammar checking,
lesson building, exercise generation, and progress tracking.
"""

from .english_models import EnglishResult
from .grammar_checker import GrammarChecker
from .lesson_builder import LessonBuilder
from .exercise_builder import ExerciseBuilder
from .progress_tracker import ProgressTracker
from .feedback_builder import FeedbackBuilder
from .learning_memory import LearningMemory


class EnglishEngine:
    """
    English Learning Engine for processing English learning requests.
    
    This engine processes user messages to detect grammar mistakes, generate
    educational lessons, create practice exercises, and track user progress.
    It uses deterministic rules only - no AI is involved.
    """
    
    def __init__(self):
        """Initialize the English engine with its components."""
        self.grammar_checker = GrammarChecker()
        self.lesson_builder = LessonBuilder()
        self.exercise_builder = ExerciseBuilder()
        self.progress_tracker = ProgressTracker()
        self.feedback_builder = FeedbackBuilder()
        self.learning_memory = LearningMemory()

    def process(self, message: str, user_id: str) -> EnglishResult:
        """
        Process an English learning request.
        
        This is the only public method of the EnglishEngine. It performs
        comprehensive analysis of the user's message to:
        - Detect and correct grammar mistakes
        - Generate educational lessons
        - Create practice exercises
        - Track user progress
        - Identify weak topics
        
        Args:
            message: The user's message to process
            user_id: The user's identifier for progress tracking
            
        Returns:
            EnglishResult containing all learning components
        """
        # Check grammar mistakes
        corrected_sentence, mistakes = self.grammar_checker.check(message)
        
        # Record mistakes for progress tracking
        for mistake in mistakes:
            self.progress_tracker.record_mistake(user_id, mistake)
        
        # Get weak topics
        weak_topics = self.progress_tracker.get_weak_topics(user_id)
        
        # Generate lesson and exercise
        lesson = None
        exercise = None
        
        # Detect explicit lesson request in Arabic or English
        msg_lower = message.lower()
        is_lesson_request = any(w in msg_lower for w in ["درس", "تعلم", "تعليم", "قواعد", "lesson", "teach", "give me a lesson", "give me a class"])
        
        if mistakes:
            lesson = self.lesson_builder.build(mistakes[0], message)
            exercise = self.exercise_builder.build(mistakes[0])
        elif is_lesson_request:
            # Generate a default past tense irregular verb lesson/exercise
            from .english_models import GrammarMistake, GrammarTopic
            default_mistake = GrammarMistake(
                mistake_type="Irregular Past Tense",
                original="go",
                correction="went",
                position=0,
                topic=GrammarTopic.PAST_TENSE
            )
            lesson = self.lesson_builder.build(default_mistake, "I go to school yesterday.")
            exercise = self.exercise_builder.build(default_mistake)
        
        return EnglishResult(
            corrected_sentence=corrected_sentence,
            mistakes=mistakes,
            lesson=lesson,
            exercise=exercise,
            weak_topics=weak_topics
        )
    
    def get_feedback(self, result: EnglishResult) -> str:
        """
        Get formatted feedback from an English result.
        
        Args:
            result: The English learning result
            
        Returns:
            Formatted feedback string
        """
        return self.feedback_builder.build(result)

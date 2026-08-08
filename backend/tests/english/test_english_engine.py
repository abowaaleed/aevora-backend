"""
Unit tests for English Engine.
"""

import pytest
from app.skills.english import EnglishEngine, EnglishResult, GrammarTopic


class TestEnglishEngine:
    """Test cases for EnglishEngine."""
    
    def test_process_with_mistakes(self, english_engine):
        """Test processing a sentence with grammar mistakes."""
        result = english_engine.process("I goed to the store", "user1")
        
        assert isinstance(result, EnglishResult)
        assert result.corrected_sentence == "I went to the store"
        assert len(result.mistakes) == 1
        assert result.mistakes[0].original == "goed"
        assert result.mistakes[0].correction == "went"
        assert result.lesson is not None
        assert result.exercise is not None
    
    def test_process_without_mistakes(self, english_engine):
        """Test processing a correct sentence."""
        result = english_engine.process("I went to the store", "user1")
        
        assert isinstance(result, EnglishResult)
        assert result.corrected_sentence == "I went to the store"
        assert len(result.mistakes) == 0
        assert result.lesson is None
        assert result.exercise is None
    
    def test_process_with_user_id(self, english_engine):
        """Test that user_id is used for progress tracking."""
        user_id = "test_user_123"
        result = english_engine.process("I goed to the store", user_id)
        
        assert isinstance(result, EnglishResult)
        assert len(result.mistakes) == 1
    
    def test_progress_tracking(self, english_engine):
        """Test that mistakes are tracked for progress."""
        user_id = "progress_user"
        
        # First mistake
        english_engine.process("I goed to the store", user_id)
        weak_topics = english_engine.progress_tracker.get_weak_topics(user_id)
        
        # Should not be weak yet (threshold is 3)
        assert len(weak_topics) == 0
        
        # Add more mistakes
        for _ in range(3):
            english_engine.process("I goed to the store", user_id)
        
        weak_topics = english_engine.progress_tracker.get_weak_topics(user_id)
        assert len(weak_topics) >= 1
    
    def test_get_feedback(self, english_engine):
        """Test feedback generation."""
        result = english_engine.process("I goed to the store", "user1")
        feedback = english_engine.get_feedback(result)
        
        assert isinstance(feedback, str)
        assert "English Learning Feedback" in feedback
        assert "I went to the store" in feedback
        assert "Lesson" in feedback
    
    def test_multiple_mistakes(self, english_engine):
        """Test processing with multiple mistakes."""
        result = english_engine.process("I have two childs and buyed a apple", "user1")
        
        assert len(result.mistakes) >= 2
        assert "children" in result.corrected_sentence
        assert "bought" in result.corrected_sentence
        assert "an apple" in result.corrected_sentence


class TestLessonBuilder:
    """Test cases for LessonBuilder."""
    
    def test_build_lesson_from_mistake(self, english_engine):
        """Test lesson building from a mistake."""
        from app.skills.english import GrammarMistake
        
        mistake = GrammarMistake(
            mistake_type="irregular_past_tense",
            original="goed",
            correction="went",
            position=1,
            topic=GrammarTopic.PAST_TENSE
        )
        
        lesson = english_engine.lesson_builder.build(mistake, "I goed to the store")
        
        assert lesson.wrong_sentence == "I goed to the store"
        assert lesson.correct_sentence == "I went to the store"
        assert lesson.explanation is not None
        assert lesson.example is not None
        assert lesson.topic == GrammarTopic.PAST_TENSE


class TestExerciseBuilder:
    """Test cases for ExerciseBuilder."""
    
    def test_build_exercise_from_mistake(self, english_engine):
        """Test exercise building from a mistake."""
        from app.skills.english import GrammarMistake
        
        mistake = GrammarMistake(
            mistake_type="irregular_past_tense",
            original="goed",
            correction="went",
            position=1,
            topic=GrammarTopic.PAST_TENSE
        )
        
        exercise = english_engine.exercise_builder.build(mistake)
        
        assert exercise.question is not None
        assert len(exercise.options) > 0
        assert exercise.correct_answer in exercise.options
        assert exercise.explanation is not None
        assert exercise.topic == GrammarTopic.PAST_TENSE


class TestProgressTracker:
    """Test cases for ProgressTracker."""
    
    def test_record_mistake(self, english_engine):
        """Test recording a mistake."""
        from app.skills.english import GrammarMistake
        
        mistake = GrammarMistake(
            mistake_type="irregular_past_tense",
            original="goed",
            correction="went",
            position=1,
            topic=GrammarTopic.PAST_TENSE
        )
        
        english_engine.progress_tracker.record_mistake("user1", mistake)
        count = english_engine.progress_tracker.get_mistake_count("user1", GrammarTopic.PAST_TENSE)
        
        assert count == 1
    
    def test_get_weak_topics_threshold(self, english_engine):
        """Test weak topics threshold."""
        from app.skills.english import GrammarMistake
        
        mistake = GrammarMistake(
            mistake_type="irregular_past_tense",
            original="goed",
            correction="went",
            position=1,
            topic=GrammarTopic.PAST_TENSE
        )
        
        user_id = "threshold_user"
        
        # Below threshold
        for _ in range(2):
            english_engine.progress_tracker.record_mistake(user_id, mistake)
        weak_topics = english_engine.progress_tracker.get_weak_topics(user_id, threshold=3)
        assert len(weak_topics) == 0
        
        # At threshold
        english_engine.progress_tracker.record_mistake(user_id, mistake)
        weak_topics = english_engine.progress_tracker.get_weak_topics(user_id, threshold=3)
        assert len(weak_topics) == 1
        assert GrammarTopic.PAST_TENSE in weak_topics
    
    def test_reset_user(self, english_engine):
        """Test resetting user progress."""
        from app.skills.english import GrammarMistake
        
        mistake = GrammarMistake(
            mistake_type="irregular_past_tense",
            original="goed",
            correction="went",
            position=1,
            topic=GrammarTopic.PAST_TENSE
        )
        
        user_id = "reset_user"
        english_engine.progress_tracker.record_mistake(user_id, mistake)
        
        english_engine.progress_tracker.reset_user(user_id)
        stats = english_engine.progress_tracker.get_all_stats(user_id)
        
        assert len(stats) == 0

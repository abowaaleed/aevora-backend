"""
Data structures for the English Learning Engine.

This module defines the types and data structures used for English learning,
following clean architecture principles with clear separation of concerns.
"""

from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field


class GrammarTopic(str, Enum):
    """Enumeration of grammar topics for tracking."""
    
    PAST_TENSE = "past_tense"
    PRESENT_TENSE = "present_tense"
    SUBJECT_VERB_AGREEMENT = "subject_verb_agreement"
    PLURAL_NOUNS = "plural_nouns"
    ARTICLES = "articles"
    PREPOSITIONS = "prepositions"
    ADJECTIVES = "adjectives"
    ADVERBS = "adverbs"


class GrammarMistake(BaseModel):
    """Model representing a detected grammar mistake."""
    
    mistake_type: str = Field(..., description="Type of grammar mistake")
    original: str = Field(..., description="Original incorrect text")
    correction: str = Field(..., description="Corrected text")
    position: int = Field(..., description="Position in the sentence")
    topic: GrammarTopic = Field(..., description="Grammar topic category")
    
    class Config:
        """Pydantic configuration."""
        use_enum_values = True


class Lesson(BaseModel):
    """Model representing an educational lesson."""
    
    wrong_sentence: str = Field(..., description="The incorrect sentence")
    correct_sentence: str = Field(..., description="The correct sentence")
    explanation: str = Field(..., description="Explanation of the grammar rule")
    example: str = Field(..., description="Example demonstrating the rule")
    topic: GrammarTopic = Field(..., description="Grammar topic")
    
    class Config:
        """Pydantic configuration."""
        use_enum_values = True


class Exercise(BaseModel):
    """Model representing a practice exercise."""
    
    question: str = Field(..., description="The exercise question")
    options: list[str] = Field(..., description="Multiple choice options")
    correct_answer: str = Field(..., description="The correct answer")
    explanation: str = Field(..., description="Explanation for the answer")
    topic: GrammarTopic = Field(..., description="Grammar topic")
    
    class Config:
        """Pydantic configuration."""
        use_enum_values = True


class EnglishResult(BaseModel):
    """Model representing the complete English learning result."""
    
    corrected_sentence: str = Field(..., description="The corrected sentence")
    mistakes: list[GrammarMistake] = Field(default_factory=list, description="Detected mistakes")
    lesson: Optional[Lesson] = Field(default=None, description="Generated lesson")
    exercise: Optional[Exercise] = Field(default=None, description="Generated exercise")
    weak_topics: list[GrammarTopic] = Field(default_factory=list, description="User's weak topics")
    
    class Config:
        """Pydantic configuration."""
        use_enum_values = True

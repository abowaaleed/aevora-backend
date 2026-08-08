"""
Progress tracker for the English Learning Engine.

This module tracks user progress and identifies weak grammar topics.
"""

from .english_models import GrammarTopic, GrammarMistake
from typing import Dict, List


class ProgressTracker:
    """Tracks user grammar progress and identifies weak topics."""
    
    def __init__(self):
        """Initialize the progress tracker with empty user data."""
        self.user_data: Dict[str, Dict[GrammarTopic, int]] = {}
    
    def record_mistake(self, user_id: str, mistake: GrammarMistake) -> None:
        """
        Record a grammar mistake for a user.
        
        Args:
            user_id: The user's identifier
            mistake: The grammar mistake to record
        """
        if user_id not in self.user_data:
            self.user_data[user_id] = {}
        
        if mistake.topic not in self.user_data[user_id]:
            self.user_data[user_id][mistake.topic] = 0
        
        self.user_data[user_id][mistake.topic] += 1
    
    def get_weak_topics(self, user_id: str, threshold: int = 3) -> List[GrammarTopic]:
        """
        Get the user's weak grammar topics.
        
        Args:
            user_id: The user's identifier
            threshold: Minimum number of mistakes to consider a topic weak
            
        Returns:
            List of weak grammar topics
        """
        if user_id not in self.user_data:
            return []
        
        weak_topics = []
        for topic, count in self.user_data[user_id].items():
            if count >= threshold:
                weak_topics.append(topic)
        
        # Sort by mistake count (most mistakes first)
        weak_topics.sort(key=lambda t: self.user_data[user_id][t], reverse=True)
        
        return weak_topics
    
    def get_mistake_count(self, user_id: str, topic: GrammarTopic) -> int:
        """
        Get the number of mistakes for a specific topic.
        
        Args:
            user_id: The user's identifier
            topic: The grammar topic
            
        Returns:
            Number of mistakes for the topic
        """
        if user_id not in self.user_data:
            return 0
        
        return self.user_data[user_id].get(topic, 0)
    
    def get_all_stats(self, user_id: str) -> Dict[GrammarTopic, int]:
        """
        Get all statistics for a user.
        
        Args:
            user_id: The user's identifier
            
        Returns:
            Dictionary of topic to mistake count
        """
        if user_id not in self.user_data:
            return {}
        
        return self.user_data[user_id].copy()
    
    def reset_user(self, user_id: str) -> None:
        """
        Reset all progress for a user.
        
        Args:
            user_id: The user's identifier
        """
        if user_id in self.user_data:
            del self.user_data[user_id]

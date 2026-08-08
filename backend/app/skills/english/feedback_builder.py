"""
Feedback builder for the English Learning Engine.

This module builds beautiful structured responses for English learning.
"""

from .english_models import EnglishResult, Lesson, Exercise


class FeedbackBuilder:
    """Builds structured educational feedback."""
    
    def build(self, result: EnglishResult) -> str:
        """
        Build a structured feedback response.
        
        Args:
            result: The English learning result
            
        Returns:
            A beautifully formatted feedback string
        """
        feedback_parts = []
        
        # Header
        feedback_parts.append("📝 English Learning Feedback")
        feedback_parts.append("=" * 40)
        feedback_parts.append("")
        
        # Corrected sentence
        feedback_parts.append(f"✅ Corrected Sentence:")
        feedback_parts.append(f"   {result.corrected_sentence}")
        feedback_parts.append("")
        
        # Mistakes
        if result.mistakes:
            feedback_parts.append(f"🔍 Found {len(result.mistakes)} mistake(s):")
            for i, mistake in enumerate(result.mistakes, 1):
                feedback_parts.append(f"   {i}. {mistake.original} → {mistake.correction}")
                feedback_parts.append(f"      ({mistake.mistake_type})")
            feedback_parts.append("")
        
        # Lesson
        if result.lesson:
            feedback_parts.append("📚 Lesson:")
            feedback_parts.append(f"   ❌ Wrong: {result.lesson.wrong_sentence}")
            feedback_parts.append(f"   ✅ Correct: {result.lesson.correct_sentence}")
            feedback_parts.append("")
            feedback_parts.append(f"   💡 Explanation:")
            feedback_parts.append(f"   {result.lesson.explanation}")
            feedback_parts.append("")
            feedback_parts.append(f"   📖 Example:")
            feedback_parts.append(f"   {result.lesson.example}")
            feedback_parts.append("")
        
        # Exercise
        if result.exercise:
            feedback_parts.append("✏️ Practice Exercise:")
            feedback_parts.append(f"   {result.exercise.question}")
            feedback_parts.append("")
            feedback_parts.append(f"   Options:")
            for i, option in enumerate(result.exercise.options, 1):
                marker = "✓" if option == result.exercise.correct_answer else " "
                feedback_parts.append(f"   {marker} {i}. {option}")
            feedback_parts.append("")
            feedback_parts.append(f"   💡 {result.exercise.explanation}")
            feedback_parts.append("")
        
        # Weak topics
        if result.weak_topics:
            feedback_parts.append("📊 Areas to Improve:")
            for topic in result.weak_topics:
                feedback_parts.append(f"   • {topic.value.replace('_', ' ').title()}")
            feedback_parts.append("")
        
        # Footer
        feedback_parts.append("Keep practicing! 🎯")
        
        return "\n".join(feedback_parts)

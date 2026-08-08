"""
Exercise builder for the English Learning Engine.

This module generates practice exercises based on detected grammar mistakes.
"""

from .english_models import Exercise, GrammarTopic, GrammarMistake
import random


class ExerciseBuilder:
    """Builds practice exercises from grammar mistakes."""
    
    def __init__(self):
        """Initialize the exercise builder with exercise templates."""
        self.exercises = {
            GrammarTopic.PAST_TENSE: [
                {
                    "question": "What is the past tense of 'go'?",
                    "options": ["goed", "went", "gone", "going"],
                    "correct": "went",
                    "explanation": "The past tense of 'go' is 'went'. This is an irregular verb."
                },
                {
                    "question": "What is the past tense of 'eat'?",
                    "options": ["eated", "ate", "eaten", "eating"],
                    "correct": "ate",
                    "explanation": "The past tense of 'eat' is 'ate'. This is an irregular verb."
                },
                {
                    "question": "What is the past tense of 'buy'?",
                    "options": ["buyed", "bought", "buying", "buys"],
                    "correct": "bought",
                    "explanation": "The past tense of 'buy' is 'bought'. This is an irregular verb."
                },
                {
                    "question": "What is the past tense of 'see'?",
                    "options": ["seed", "saw", "seen", "seeing"],
                    "correct": "saw",
                    "explanation": "The past tense of 'see' is 'saw'. This is an irregular verb."
                }
            ],
            GrammarTopic.SUBJECT_VERB_AGREEMENT: [
                {
                    "question": "Choose the correct form: He _____ to school every day.",
                    "options": ["go", "goes", "going", "gone"],
                    "correct": "goes",
                    "explanation": "With 'he' (singular subject), use 'goes' (singular verb)."
                },
                {
                    "question": "Choose the correct form: They _____ to school every day.",
                    "options": ["goes", "go", "going", "gone"],
                    "correct": "go",
                    "explanation": "With 'they' (plural subject), use 'go' (plural verb)."
                },
                {
                    "question": "Choose the correct form: She _____ happy.",
                    "options": ["is", "are", "am", "be"],
                    "correct": "is",
                    "explanation": "With 'she' (singular subject), use 'is' (singular verb)."
                },
                {
                    "question": "Choose the correct form: We _____ happy.",
                    "options": ["is", "are", "am", "be"],
                    "correct": "are",
                    "explanation": "With 'we' (plural subject), use 'are' (plural verb)."
                }
            ],
            GrammarTopic.PLURAL_NOUNS: [
                {
                    "question": "What is the plural of 'child'?",
                    "options": ["childs", "children", "childes", "child"],
                    "correct": "children",
                    "explanation": "The plural of 'child' is 'children'. This is an irregular plural."
                },
                {
                    "question": "What is the plural of 'person'?",
                    "options": ["persons", "people", "peoples", "person"],
                    "correct": "people",
                    "explanation": "The plural of 'person' is 'people'. This is an irregular plural."
                },
                {
                    "question": "What is the plural of 'man'?",
                    "options": ["mans", "men", "manes", "man"],
                    "correct": "men",
                    "explanation": "The plural of 'man' is 'men'. This is an irregular plural."
                },
                {
                    "question": "What is the plural of 'woman'?",
                    "options": ["womans", "women", "womanes", "woman"],
                    "correct": "women",
                    "explanation": "The plural of 'woman' is 'women'. This is an irregular plural."
                }
            ],
            GrammarTopic.ARTICLES: [
                {
                    "question": "Choose the correct article: _____ apple.",
                    "options": ["a", "an", "the", "no article"],
                    "correct": "an",
                    "explanation": "Use 'an' before words starting with a vowel sound like 'apple'."
                },
                {
                    "question": "Choose the correct article: _____ book.",
                    "options": ["an", "a", "the", "no article"],
                    "correct": "a",
                    "explanation": "Use 'a' before words starting with a consonant sound like 'book'."
                },
                {
                    "question": "Choose the correct article: _____ orange.",
                    "options": ["a", "an", "the", "no article"],
                    "correct": "an",
                    "explanation": "Use 'an' before words starting with a vowel sound like 'orange'."
                },
                {
                    "question": "Choose the correct article: _____ car.",
                    "options": ["an", "a", "the", "no article"],
                    "correct": "a",
                    "explanation": "Use 'a' before words starting with a consonant sound like 'car'."
                }
            ],
            GrammarTopic.PRESENT_TENSE: [
                {
                    "question": "Choose the correct sentence:",
                    "options": ["I don't have nothing.", "I don't have anything.", "I doesn't have anything.", "I no have anything."],
                    "correct": "I don't have anything.",
                    "explanation": "Avoid double negatives. Use 'don't have anything' instead of 'don't have nothing'."
                },
                {
                    "question": "Choose the correct sentence:",
                    "options": ["I never go nowhere.", "I never go anywhere.", "I never goes anywhere.", "I no go anywhere."],
                    "correct": "I never go anywhere.",
                    "explanation": "Avoid double negatives. Use 'never go anywhere' instead of 'never go nowhere'."
                }
            ]
        }
    
    def build(self, mistake: GrammarMistake) -> Exercise:
        """
        Build an exercise based on a grammar mistake.
        
        Args:
            mistake: The grammar mistake to create an exercise for
            
        Returns:
            An Exercise object with practice question
        """
        exercises = self.exercises.get(mistake.topic, [])
        
        if exercises:
            # Select a random exercise for the topic
            exercise_data = random.choice(exercises)
            
            return Exercise(
                question=exercise_data["question"],
                options=exercise_data["options"],
                correct_answer=exercise_data["correct"],
                explanation=exercise_data["explanation"],
                topic=mistake.topic
            )
        
        # Fallback exercise if no specific exercises available
        return self._build_fallback_exercise(mistake)
    
    def _build_fallback_exercise(self, mistake: GrammarMistake) -> Exercise:
        """Build a fallback exercise when no specific exercises are available."""
        return Exercise(
            question=f"Which is correct: '{mistake.original}' or '{mistake.correction}'?",
            options=[mistake.original, mistake.correction, "Both are correct", "Neither is correct"],
            correct_answer=mistake.correction,
            explanation=f"The correct form is '{mistake.correction}'.",
            topic=mistake.topic
        )

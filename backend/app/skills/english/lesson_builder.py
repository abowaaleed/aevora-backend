"""
Lesson builder for the English Learning Engine.

This module generates structured educational lessons based on detected mistakes.
"""

from .english_models import Lesson, GrammarTopic, GrammarMistake


class LessonBuilder:
    """Builds educational lessons from grammar mistakes."""
    
    def __init__(self):
        """Initialize the lesson builder with grammar explanations."""
        self.explanations = {
            GrammarTopic.PAST_TENSE: {
                "title": "Irregular Past Tense Verbs",
                "explanation": "Some verbs have irregular past tense forms that don't follow the regular '-ed' pattern. You must memorize these forms.",
                "examples": {
                    "go": "I go to school everyday. Yesterday I went to school.",
                    "eat": "I eat breakfast at 7 AM. I ate breakfast at 7 AM yesterday.",
                    "buy": "I buy groceries every week. I bought groceries last week.",
                    "see": "I see my friends on weekends. I saw my friends last weekend."
                }
            },
            GrammarTopic.SUBJECT_VERB_AGREEMENT: {
                "title": "Subject-Verb Agreement",
                "explanation": "In English, the verb must agree with the subject in number and person. Singular subjects take singular verbs, and plural subjects take plural verbs.",
                "examples": {
                    "doesn't": "He doesn't go to school. (not 'doesn't goes')",
                    "don't": "They don't go to school. (not 'doesn't')",
                    "is": "He is happy. (not 'is are')"
                }
            },
            GrammarTopic.PLURAL_NOUNS: {
                "title": "Irregular Plural Nouns",
                "explanation": "Some nouns have irregular plural forms that don't follow the regular '-s' pattern. These must be memorized.",
                "examples": {
                    "child": "One child, two children.",
                    "person": "One person, many people.",
                    "man": "One man, two men.",
                    "woman": "One woman, two women."
                }
            },
            GrammarTopic.ARTICLES: {
                "title": "Article Usage",
                "explanation": "Use 'a' before words starting with a consonant sound, and 'an' before words starting with a vowel sound.",
                "examples": {
                    "a": "A book, a car, a dog.",
                    "an": "An apple, an egg, an orange."
                }
            },
            GrammarTopic.PRESENT_TENSE: {
                "title": "Double Negatives",
                "explanation": "In English, using two negative words in the same sentence is considered incorrect. Use only one negative word.",
                "examples": {
                    "not": "I don't have anything. (not 'I don't have nothing')",
                    "never": "I never go there. (not 'I never go nowhere')"
                }
            }
        }
    
    def build(self, mistake: GrammarMistake, original_sentence: str) -> Lesson:
        """
        Build a lesson from a grammar mistake.
        
        Args:
            mistake: The grammar mistake to create a lesson for
            original_sentence: The original incorrect sentence
            
        Returns:
            A Lesson object with structured educational content
        """
        topic_data = self.explanations.get(mistake.topic, self._get_default_explanation(mistake.topic))
        
        # Generate explanation
        explanation = self._generate_explanation(mistake, topic_data)
        
        # Generate example
        example = self._generate_example(mistake, topic_data)
        
        return Lesson(
            wrong_sentence=original_sentence,
            correct_sentence=original_sentence.replace(mistake.original, mistake.correction),
            explanation=explanation,
            example=example,
            topic=mistake.topic
        )
    
    def _generate_explanation(self, mistake: GrammarMistake, topic_data: dict) -> str:
        """Generate a specific explanation for the mistake."""
        base_explanation = topic_data.get("explanation", "")
        
        specific = f"You wrote '{mistake.original}' but the correct form is '{mistake.correction}'. "
        specific += base_explanation
        
        return specific
    
    def _generate_example(self, mistake: GrammarMistake, topic_data: dict) -> str:
        """Generate an example demonstrating the rule."""
        examples = topic_data.get("examples", {})
        
        # Try to find a relevant example
        if mistake.original.lower() in examples:
            return examples[mistake.original.lower()]
        
        # Return any available example
        if examples:
            return list(examples.values())[0]
        
        return f"Correct: {mistake.correction} | Incorrect: {mistake.original}"
    
    def _get_default_explanation(self, topic: GrammarTopic) -> dict:
        """Get default explanation for unknown topics."""
        return {
            "title": "Grammar Rule",
            "explanation": "This is a grammar rule that should be followed for proper English usage.",
            "examples": {}
        }

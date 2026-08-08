"""
Grammar checker for the English Learning Engine.

This module uses deterministic rules to detect common grammar mistakes.
No AI is used - only pattern matching and rule-based detection.
"""

import re
from .english_models import GrammarMistake, GrammarTopic


class GrammarChecker:
    """Detects grammar mistakes using deterministic rules."""
    
    def __init__(self):
        """Initialize the grammar checker with common mistake patterns."""
        self.irregular_verbs = {
            "go": "went",
            "went": "gone",
            "eat": "ate",
            "ate": "eaten",
            "buy": "bought",
            "bought": "bought",
            "see": "saw",
            "saw": "seen",
            "do": "did",
            "did": "done",
            "make": "made",
            "made": "made",
            "take": "took",
            "took": "taken",
            "write": "wrote",
            "wrote": "written",
            "speak": "spoke",
            "spoke": "spoken",
            "give": "gave",
            "gave": "given",
            "come": "came",
            "came": "come",
            "know": "knew",
            "knew": "known",
            "think": "thought",
            "thought": "thought",
            "bring": "brought",
            "brought": "brought",
            "catch": "caught",
            "caught": "caught",
            "teach": "taught",
            "taught": "taught",
            "fight": "fought",
            "fought": "fought",
            "find": "found",
            "found": "found",
            "hear": "heard",
            "heard": "heard",
            "hold": "held",
            "held": "held",
            "keep": "kept",
            "kept": "kept",
            "leave": "left",
            "left": "left",
            "lose": "lost",
            "lost": "lost",
            "meet": "met",
            "met": "met",
            "pay": "paid",
            "paid": "paid",
            "read": "read",
            "read": "read",
            "say": "said",
            "said": "said",
            "sell": "sold",
            "sold": "sold",
            "send": "sent",
            "sent": "sent",
            "shine": "shone",
            "shone": "shone",
            "shoot": "shot",
            "shot": "shot",
            "sit": "sat",
            "sat": "sat",
            "sleep": "slept",
            "slept": "slept",
            "spend": "spent",
            "spent": "spent",
            "stand": "stood",
            "stood": "stood",
            "sweep": "swept",
            "swept": "swept",
            "teach": "taught",
            "taught": "taught",
            "tell": "told",
            "told": "told",
            "understand": "understood",
            "understood": "understood",
            "win": "won",
            "won": "won"
        }
        
        self.irregular_nouns = {
            "child": "children",
            "person": "people",
            "man": "men",
            "woman": "women",
            "tooth": "teeth",
            "foot": "feet",
            "mouse": "mice",
            "goose": "geese",
            "ox": "oxen",
            "leaf": "leaves",
            "life": "lives",
            "knife": "knives",
            "wife": "wives",
            "half": "halves",
            "self": "selves",
            "calf": "calves",
            "loaf": "loaves",
            "wolf": "wolves",
            "thief": "thieves",
            "shelf": "shelves"
        }
    
    def check(self, sentence: str) -> tuple[str, list[GrammarMistake]]:
        """
        Check a sentence for grammar mistakes.
        
        Args:
            sentence: The sentence to check
            
        Returns:
            Tuple of (corrected_sentence, list_of_mistakes)
        """
        mistakes = []
        corrected = sentence
        
        # Check for common mistakes
        corrected, new_mistakes = self._check_irregular_past_tense(corrected)
        mistakes.extend(new_mistakes)
        
        corrected, new_mistakes = self._check_subject_verb_agreement(corrected)
        mistakes.extend(new_mistakes)
        
        corrected, new_mistakes = self._check_irregular_plurals(corrected)
        mistakes.extend(new_mistakes)
        
        corrected, new_mistakes = self._check_double_negatives(corrected)
        mistakes.extend(new_mistakes)
        
        corrected, new_mistakes = self._check_article_usage(corrected)
        mistakes.extend(new_mistakes)
        
        return corrected, mistakes
    
    def _check_irregular_past_tense(self, sentence: str) -> tuple[str, list[GrammarMistake]]:
        """Check for incorrect irregular past tense forms."""
        mistakes = []
        corrected = sentence
        words = sentence.split()
        
        for i, word in enumerate(words):
            # Check for common incorrect forms like "goed", "eated", "buyed"
            if word.endswith("ed"):
                base = word[:-2]
                if base in self.irregular_verbs:
                    correct = self.irregular_verbs[base]
                    if word != correct:
                        mistakes.append(GrammarMistake(
                            mistake_type="irregular_past_tense",
                            original=word,
                            correction=correct,
                            position=i,
                            topic=GrammarTopic.PAST_TENSE
                        ))
                        words[i] = correct
        
        return " ".join(words), mistakes
    
    def _check_subject_verb_agreement(self, sentence: str) -> tuple[str, list[GrammarMistake]]:
        """Check for subject-verb agreement errors."""
        mistakes = []
        corrected = sentence
        words = sentence.split()
        
        # Check for "doesn't goes", "don't goes", "is are" patterns
        for i in range(len(words) - 1):
            current = words[i].lower()
            next_word = words[i + 1].lower()
            
            # "doesn't goes" -> "doesn't go"
            if current == "doesn't" and next_word == "goes":
                mistakes.append(GrammarMistake(
                    mistake_type="subject_verb_agreement",
                    original="doesn't goes",
                    correction="doesn't go",
                    position=i,
                    topic=GrammarTopic.SUBJECT_VERB_AGREEMENT
                ))
                words[i + 1] = "go"
            
            # "is are" -> "is"
            if current == "is" and next_word == "are":
                mistakes.append(GrammarMistake(
                    mistake_type="subject_verb_agreement",
                    original="is are",
                    correction="is",
                    position=i,
                    topic=GrammarTopic.SUBJECT_VERB_AGREEMENT
                ))
                words[i + 1] = ""
            
            # "don't goes" -> "doesn't go"
            if current == "don't" and next_word == "goes":
                mistakes.append(GrammarMistake(
                    mistake_type="subject_verb_agreement",
                    original="don't goes",
                    correction="doesn't go",
                    position=i,
                    topic=GrammarTopic.SUBJECT_VERB_AGREEMENT
                ))
                words[i] = "doesn't"
                words[i + 1] = "go"
        
        # Remove empty strings
        words = [w for w in words if w]
        return " ".join(words), mistakes
    
    def _check_irregular_plurals(self, sentence: str) -> tuple[str, list[GrammarMistake]]:
        """Check for incorrect irregular plural forms."""
        mistakes = []
        corrected = sentence
        words = sentence.split()
        
        for i, word in enumerate(words):
            # Remove punctuation for checking
            clean_word = word.lower().rstrip(".,!?;:")
            
            # Check for incorrect plurals like "childs", "persons", "mans"
            if clean_word.endswith("s"):
                base = clean_word[:-1]
                if base in self.irregular_nouns:
                    correct = self.irregular_nouns[base]
                    if clean_word != correct:
                        mistakes.append(GrammarMistake(
                            mistake_type="irregular_plural",
                            original=clean_word,
                            correction=correct,
                            position=i,
                            topic=GrammarTopic.PLURAL_NOUNS
                        ))
                        # Preserve punctuation
                        punctuation = word[len(clean_word):]
                        words[i] = correct + punctuation
        
        return " ".join(words), mistakes
    
    def _check_double_negatives(self, sentence: str) -> tuple[str, list[GrammarMistake]]:
        """Check for double negatives."""
        mistakes = []
        words = sentence.split()
        
        # 1. Non-consecutive check: e.g. "I don't have nothing" -> "I don't have anything"
        has_negative_modifier = False
        for word in words:
            clean = word.lower().rstrip(".,!?;:")
            if clean == "not" or clean.endswith("n't"):
                has_negative_modifier = True
                break
                
        if has_negative_modifier:
            replacements = {
                "nothing": "anything",
                "nobody": "anybody",
                "nowhere": "anywhere",
                "no": "any"
            }
            for i, word in enumerate(words):
                clean_word = word.lower().rstrip(".,!?;:")
                if clean_word in replacements:
                    correct_word = replacements[clean_word]
                    if word.istitle():
                        correct_word = correct_word.capitalize()
                    elif word.isupper():
                        correct_word = correct_word.upper()
                    
                    punctuation = word[len(clean_word):]
                    corrected_word = correct_word + punctuation
                    
                    mistakes.append(GrammarMistake(
                        mistake_type="double_negative",
                        original=clean_word,
                        correction=correct_word,
                        position=i,
                        topic=GrammarTopic.PRESENT_TENSE
                    ))
                    words[i] = corrected_word
                    
        # 2. Consecutive check: e.g. "no never"
        negative_words = ["not", "no", "never", "nothing", "nobody", "nowhere", "neither", "nor"]
        i = 0
        while i < len(words) - 1:
            if not words[i]:
                i += 1
                continue
            current = words[i].lower().rstrip(".,!?;:")
            
            # Find next non-empty word
            next_idx = i + 1
            while next_idx < len(words) and not words[next_idx]:
                next_idx += 1
            if next_idx >= len(words):
                break
                
            next_word = words[next_idx].lower().rstrip(".,!?;:")
            
            if current in negative_words and next_word in negative_words:
                mistakes.append(GrammarMistake(
                    mistake_type="double_negative",
                    original=f"{current} {next_word}",
                    correction=current,
                    position=i,
                    topic=GrammarTopic.PRESENT_TENSE
                ))
                words[next_idx] = ""
            i += 1
            
        words = [w for w in words if w]
        return " ".join(words), mistakes
    
    def _check_article_usage(self, sentence: str) -> tuple[str, list[GrammarMistake]]:
        """Check for article usage errors."""
        mistakes = []
        corrected = sentence
        words = sentence.split()
        
        vowels = "aeiou"
        
        for i in range(len(words) - 1):
            current = words[i].lower()
            next_word = words[i + 1].lower()
            
            # "a apple" -> "an apple"
            if current == "a" and next_word and next_word[0] in vowels:
                mistakes.append(GrammarMistake(
                    mistake_type="article_usage",
                    original=f"a {next_word}",
                    correction=f"an {next_word}",
                    position=i,
                    topic=GrammarTopic.ARTICLES
                ))
                words[i] = "an"
            
            # "an book" -> "a book"
            if current == "an" and next_word and next_word[0] not in vowels:
                mistakes.append(GrammarMistake(
                    mistake_type="article_usage",
                    original=f"an {next_word}",
                    correction=f"a {next_word}",
                    position=i,
                    topic=GrammarTopic.ARTICLES
                ))
                words[i] = "a"
        
        return " ".join(words), mistakes

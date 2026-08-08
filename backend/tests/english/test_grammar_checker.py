"""
Unit tests for Grammar Checker.
"""

import pytest
from app.skills.english import GrammarChecker, GrammarTopic


class TestGrammarChecker:
    """Test cases for GrammarChecker."""
    
    def test_check_irregular_past_tense_goed(self):
        """Test detection of 'goed' -> 'went'."""
        checker = GrammarChecker()
        corrected, mistakes = checker.check("I goed to the store")
        
        assert corrected == "I went to the store"
        assert len(mistakes) == 1
        assert mistakes[0].original == "goed"
        assert mistakes[0].correction == "went"
        assert mistakes[0].topic == GrammarTopic.PAST_TENSE
    
    def test_check_irregular_past_tense_ated(self):
        """Test detection of 'eated' -> 'ate'."""
        checker = GrammarChecker()
        corrected, mistakes = checker.check("I eated an apple")
        
        assert corrected == "I ate an apple"
        assert len(mistakes) == 1
        assert mistakes[0].original == "eated"
        assert mistakes[0].correction == "ate"
    
    def test_check_irregular_past_tense_buyed(self):
        """Test detection of 'buyed' -> 'bought'."""
        checker = GrammarChecker()
        corrected, mistakes = checker.check("I buyed a car")
        
        assert corrected == "I bought a car"
        assert len(mistakes) == 1
        assert mistakes[0].original == "buyed"
        assert mistakes[0].correction == "bought"
    
    def test_check_subject_verb_agreement_doesnt_goes(self):
        """Test detection of 'doesn't goes' -> 'doesn't go'."""
        checker = GrammarChecker()
        corrected, mistakes = checker.check("He doesn't goes to school")
        
        assert corrected == "He doesn't go to school"
        assert len(mistakes) == 1
        assert mistakes[0].original == "doesn't goes"
        assert mistakes[0].correction == "doesn't go"
        assert mistakes[0].topic == GrammarTopic.SUBJECT_VERB_AGREEMENT
    
    def test_check_subject_verb_agreement_is_are(self):
        """Test detection of 'is are' -> 'is'."""
        checker = GrammarChecker()
        corrected, mistakes = checker.check("He is are happy")
        
        assert "is are" not in corrected
        assert len(mistakes) >= 1
    
    def test_check_irregular_plurals_childs(self):
        """Test detection of 'childs' -> 'children'."""
        checker = GrammarChecker()
        corrected, mistakes = checker.check("I have two childs")
        
        assert corrected == "I have two children"
        assert len(mistakes) == 1
        assert mistakes[0].original == "childs"
        assert mistakes[0].correction == "children"
        assert mistakes[0].topic == GrammarTopic.PLURAL_NOUNS
    
    def test_check_irregular_plurals_persons(self):
        """Test detection of 'persons' -> 'people'."""
        checker = GrammarChecker()
        corrected, mistakes = checker.check("There are many persons")
        
        assert corrected == "There are many people"
        assert len(mistakes) == 1
        assert mistakes[0].original == "persons"
        assert mistakes[0].correction == "people"
    
    def test_check_double_negatives(self):
        """Test detection of double negatives."""
        checker = GrammarChecker()
        corrected, mistakes = checker.check("I don't have nothing")
        
        assert "nothing" not in corrected
        assert len(mistakes) >= 1
    
    def test_check_article_usage_a_apple(self):
        """Test detection of 'a apple' -> 'an apple'."""
        checker = GrammarChecker()
        corrected, mistakes = checker.check("I have a apple")
        
        assert corrected == "I have an apple"
        assert len(mistakes) == 1
        assert mistakes[0].original == "a apple"
        assert mistakes[0].correction == "an apple"
        assert mistakes[0].topic == GrammarTopic.ARTICLES
    
    def test_check_article_usage_an_book(self):
        """Test detection of 'an book' -> 'a book'."""
        checker = GrammarChecker()
        corrected, mistakes = checker.check("I have an book")
        
        assert corrected == "I have a book"
        assert len(mistakes) == 1
        assert mistakes[0].original == "an book"
        assert mistakes[0].correction == "a book"
    
    def test_check_no_mistakes(self):
        """Test that correct sentences have no mistakes."""
        checker = GrammarChecker()
        corrected, mistakes = checker.check("I went to the store yesterday")
        
        assert len(mistakes) == 0
        assert corrected == "I went to the store yesterday"
    
    def test_check_multiple_mistakes(self):
        """Test detection of multiple mistakes in one sentence."""
        checker = GrammarChecker()
        corrected, mistakes = checker.check("I goed to the store and buyed a apple")
        
        assert len(mistakes) >= 2
        assert "went" in corrected
        assert "bought" in corrected
        assert "an apple" in corrected
    
    def test_check_preserves_punctuation(self):
        """Test that punctuation is preserved."""
        checker = GrammarChecker()
        corrected, mistakes = checker.check("I have two childs.")
        
        assert corrected.endswith(".")
        assert "children." in corrected
    
    def test_check_irregular_verbs_dictionary(self):
        """Test that irregular verbs dictionary is populated."""
        checker = GrammarChecker()
        assert len(checker.irregular_verbs) > 0
        assert "go" in checker.irregular_verbs
        assert checker.irregular_verbs["go"] == "went"
    
    def test_check_irregular_nouns_dictionary(self):
        """Test that irregular nouns dictionary is populated."""
        checker = GrammarChecker()
        assert len(checker.irregular_nouns) > 0
        assert "child" in checker.irregular_nouns
        assert checker.irregular_nouns["child"] == "children"

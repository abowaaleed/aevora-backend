"""
Unit tests for Prompt Builder.
"""

import pytest
from app.prompt_engine import PromptBuilder, SystemPrompt, SkillPrompt, PromptLoader
from app.prompt_engine.types import Skill, PromptContext, BuiltPrompt


class TestPromptLoader:
    """Test cases for PromptLoader."""
    
    def test_load_file_exists(self, prompt_loader):
        """Test loading an existing file."""
        content = prompt_loader.load("system.md")
        assert content is not None
        assert len(content) > 0
    
    def test_load_system_prompt(self, prompt_loader):
        """Test loading system prompt."""
        content = prompt_loader.load_system_prompt()
        assert content is not None
        assert "Aevora" in content
    
    def test_load_skill_prompt(self, prompt_loader):
        """Test loading skill prompt."""
        content = prompt_loader.load_skill_prompt("quick")
        assert content is not None
        assert len(content) > 0


class TestSystemPrompt:
    """Test cases for SystemPrompt."""
    
    def test_get_content(self, system_prompt):
        """Test getting system prompt content."""
        content = system_prompt.get()
        assert content is not None
        assert "Aevora" in content
    
    def test_caching(self, system_prompt):
        """Test that system prompt is cached."""
        content1 = system_prompt.get()
        content2 = system_prompt.get()
        assert content1 == content2


class TestSkillPrompt:
    """Test cases for SkillPrompt."""
    
    def test_get_content(self, skill_prompt):
        """Test getting skill prompt content."""
        content = skill_prompt.get("quick")
        assert content is not None
        assert len(content) > 0
    
    def test_get_different_skills(self, skill_prompt):
        """Test getting different skill prompts."""
        quick_content = skill_prompt.get("quick")
        english_content = skill_prompt.get("english")
        
        assert quick_content is not None
        assert english_content is not None
        assert quick_content != english_content
    
    def test_caching(self, skill_prompt):
        """Test that skill prompts are cached."""
        content1 = skill_prompt.get("quick")
        content2 = skill_prompt.get("quick")
        assert content1 == content2


class TestPromptBuilder:
    """Test cases for PromptBuilder."""
    
    def test_build_prompt(self, prompt_builder):
        """Test building a complete prompt."""
        context = PromptContext(
            skill=Skill.QUICK,
            user_message="Hello, how are you?",
            conversation_history=[]
        )
        
        built_prompt = prompt_builder.build(
            skill=Skill.QUICK,
            user_message="Hello, how are you?",
            context=context
        )
        
        assert isinstance(built_prompt, BuiltPrompt)
        assert built_prompt.content is not None
        assert len(built_prompt.content) > 0
    
    def test_build_prompt_with_context(self, prompt_builder):
        """Test building prompt with conversation context."""
        context = PromptContext(
            skill=Skill.ENGLISH,
            user_message="What is the past tense of go?",
            conversation_history=[
                {"role": "user", "content": "Hello"},
                {"role": "assistant", "content": "Hi there!"}
            ]
        )
        
        built_prompt = prompt_builder.build(
            skill=Skill.ENGLISH,
            user_message="What is the past tense of go?",
            context=context
        )
        
        assert isinstance(built_prompt, BuiltPrompt)
        assert built_prompt.content is not None
    
    def test_build_prompt_different_skills(self, prompt_builder):
        """Test building prompts for different skills."""
        skills = [Skill.QUICK, Skill.ENGLISH, Skill.PROGRAMMER]
        
        for skill in skills:
            context = PromptContext(
                skill=skill,
                user_message="Test message",
                conversation_history=[]
            )
            
            built_prompt = prompt_builder.build(
                skill=skill,
                user_message="Test",
                context=context
            )
            assert isinstance(built_prompt, BuiltPrompt)
            assert built_prompt.content is not None

"""
Unit tests for Ollama Provider with mocking.
"""

import pytest
from unittest.mock import Mock, patch
from app.providers.ollama_provider import OllamaProvider


class TestOllamaProvider:
    """Test cases for OllamaProvider with mocking."""
    
    @patch('app.providers.ollama_provider.requests.post')
    def test_generate_success(self, mock_post):
        """Test successful generation with mocked API."""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "response": "Test AI response"
        }
        mock_post.return_value = mock_response
        
        provider = OllamaProvider()
        result = provider.generate("Test prompt")
        
        assert result == "Test AI response"
        mock_post.assert_called_once()
    
    @patch('app.providers.ollama_provider.requests.post')
    def test_generate_with_custom_model(self, mock_post):
        """Test generation with custom model."""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "response": "Custom model response"
        }
        mock_post.return_value = mock_response
        
        provider = OllamaProvider(model="llama2")
        result = provider.generate("Test prompt")
        
        assert result == "Custom model response"
    
    @patch('app.providers.ollama_provider.requests.post')
    def test_generate_api_error(self, mock_post):
        """Test handling of API errors."""
        mock_response = Mock()
        mock_response.status_code = 500
        mock_post.return_value = mock_response
        
        provider = OllamaProvider()
        
        with pytest.raises(Exception):
            provider.generate("Test prompt")
    
    @patch('app.providers.ollama_provider.requests.post')
    def test_generate_timeout(self, mock_post):
        """Test handling of timeout."""
        import requests
        mock_post.side_effect = requests.exceptions.Timeout()
        
        provider = OllamaProvider()
        
        with pytest.raises(Exception):
            provider.generate("Test prompt")
    
    @patch('app.providers.ollama_provider.requests.post')
    def test_generate_connection_error(self, mock_post):
        """Test handling of connection errors."""
        import requests
        mock_post.side_effect = requests.exceptions.ConnectionError()
        
        provider = OllamaProvider()
        
        with pytest.raises(Exception):
            provider.generate("Test prompt")
    
    def test_provider_initialization(self):
        """Test provider initialization with default values."""
        provider = OllamaProvider()
        
        assert provider.base_url == "http://localhost:11434"
        assert provider.model == "qwen2.5:3b"
        assert provider.timeout == 90
    
    def test_provider_custom_base_url(self):
        """Test provider with custom base URL."""
        provider = OllamaProvider(base_url="http://custom:8080")
        
        assert provider.base_url == "http://custom:8080"
    
    def test_provider_custom_timeout(self):
        """Test provider with custom timeout."""
        provider = OllamaProvider(timeout=60)
        
        assert provider.timeout == 60

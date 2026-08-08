"""
Integration tests for Chat API.
"""

import pytest
from fastapi.testclient import TestClient
from unittest.mock import Mock, patch
from main import app


client = TestClient(app)


class TestHealthAPI:
    """Test cases for Health API."""
    
    def test_health_endpoint(self):
        """Test health check endpoint."""
        response = client.get("/health")
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"


class TestChatAPI:
    """Test cases for Chat API."""
    
    @patch('app.providers.ollama_provider.requests.post')
    def test_chat_endpoint_success(self, mock_post):
        """Test successful chat endpoint."""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "response": "Hello! How can I help you?"
        }
        mock_post.return_value = mock_response
        
        response = client.post("/chat", json={
            "message": "Hello",
            "skill": "quick"
        })
        
        assert response.status_code == 200
        data = response.json()
        assert "reply" in data
        assert "skill_used" in data
    
    @patch('app.providers.ollama_provider.requests.post')
    def test_chat_endpoint_with_english_skill(self, mock_post):
        """Test chat endpoint with English skill."""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "response": "I went to the store"
        }
        mock_post.return_value = mock_response
        
        response = client.post("/chat", json={
            "message": "I goed to the store",
            "skill": "english"
        })
        
        assert response.status_code == 200
        data = response.json()
        assert "reply" in data
        assert data["skill_used"] == "english"
    
    @patch('app.providers.ollama_provider.requests.post')
    def test_chat_endpoint_default_skill(self, mock_post):
        """Test chat endpoint with default skill."""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "response": "Test response"
        }
        mock_post.return_value = mock_response
        
        response = client.post("/chat", json={
            "message": "Hello"
        })
        
        assert response.status_code == 200
        data = response.json()
        assert "reply" in data
    
    def test_chat_endpoint_missing_message(self):
        """Test chat endpoint with missing message."""
        response = client.post("/chat", json={
            "skill": "quick"
        })
        
        assert response.status_code == 422  # Validation error
    
    def test_chat_endpoint_invalid_skill(self):
        """Test chat endpoint with invalid skill."""
        with patch('app.providers.ollama_provider.requests.post') as mock_post:
            mock_response = Mock()
            mock_response.status_code = 200
            mock_response.json.return_value = {"response": "Test"}
            mock_post.return_value = mock_response
            
            response = client.post("/chat", json={
                "message": "Hello",
                "skill": "invalid_skill"
            })
            
            # Should still work, skill detection will handle it
            assert response.status_code == 200
    
    @patch('app.providers.ollama_provider.requests.post')
    def test_chat_endpoint_with_session_id(self, mock_post):
        """Test chat endpoint with session ID."""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "response": "Test response"
        }
        mock_post.return_value = mock_response
        
        response = client.post("/chat", json={
            "message": "Hello",
            "skill": "quick",
            "session_id": "test_session_123"
        })
        
        assert response.status_code == 200
        data = response.json()
        assert "reply" in data

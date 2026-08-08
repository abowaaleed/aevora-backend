from app.providers.base_provider import BaseProvider


class AIEngine:
    """
    AI Engine for generating AI responses.
    This service abstracts the AI model implementation using dependency injection.
    """

    def __init__(self, provider: BaseProvider):
        """
        Initialize the AI Engine with a provider.
        
        Args:
            provider: The AI model provider to use
        """
        self.provider = provider

    def generate_reply(self, user_message: str) -> str:
        """
        Generate a reply to the user's message (legacy method).
        
        Args:
            user_message: The message from the user
            
        Returns:
            The AI-generated reply
        """
        return self.provider.generate(user_message)

    def generate_with_prompt(self, complete_prompt: str, **kwargs) -> str:
        """
        Generate a response using a complete prompt from the Prompt Engine.
        
        This method receives a fully assembled prompt (system + skill + context + message)
        and sends it directly to the provider. This is the new recommended approach
        as it uses the Prompt Engine for all prompt construction.
        
        Args:
            complete_prompt: The complete assembled prompt from PromptBuilder
            
        Returns:
            The AI-generated response
        """
        return self.provider.generate(complete_prompt, **kwargs)

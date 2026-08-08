from abc import ABC, abstractmethod
from app.runtime.stages.models import ValidationResult

class ResponseValidator(ABC):
    """
    Abstract interface for response validators.
    """
    @abstractmethod
    async def validate(self, question: str, answer: str, context: dict) -> ValidationResult:
        """
        Validate a proposed answer to a question under a given context.
        """
        pass

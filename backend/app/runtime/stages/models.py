from dataclasses import dataclass
from enum import Enum

class ValidationVerdict(str, Enum):
    APPROVED = "approved"
    UNCERTAIN = "uncertain"
    REJECTED = "rejected"

@dataclass
class ValidationResult:
    verdict: ValidationVerdict
    reason: str
    confidence: float

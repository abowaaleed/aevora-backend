import re
from typing import Any, Dict
from app.plugins.base import BasePlugin


class CalculatorPlugin(BasePlugin):
    """
    Calculator plugin for performing safe mathematical calculations.
    """

    @property
    def name(self) -> str:
        return "calculator"

    @property
    def description(self) -> str:
        return "Calculate mathematical expressions. Useful for arithmetic queries."

    def execute(self, expression: str, **kwargs: Any) -> Dict[str, Any]:
        """
        Safely execute a mathematical expression.
        """
        # Sanitize expression: only allow numbers, basic math operators, parentheses, and spaces
        sanitized = re.sub(r"[^\d+\-*/().\s]", "", expression)
        sanitized = sanitized.strip()

        if not sanitized:
            return {"success": False, "error": "Empty or invalid mathematical expression."}

        try:
            # Safely evaluate using a restricted scope
            # Note: eval is safe here because we stripped all non-math characters
            result = eval(sanitized, {"__builtins__": None}, {})
            return {
                "success": True,
                "expression": expression,
                "sanitized_expression": sanitized,
                "result": str(result)
            }
        except Exception as e:
            return {
                "success": False,
                "expression": expression,
                "error": f"Failed to calculate: {str(e)}"
            }

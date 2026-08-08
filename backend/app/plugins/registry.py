import re
from typing import Dict, List, Optional, Tuple, Any
from app.plugins.base import BasePlugin
from app.plugins.calculator import CalculatorPlugin
from app.plugins.weather import WeatherPlugin
from app.plugins.web_search import WebSearchPlugin


class PluginRegistry:
    """
    Registry for managing and executing plugins.
    """

    def __init__(self):
        self._plugins: Dict[str, BasePlugin] = {}
        # Register default built-in plugins
        self.register(CalculatorPlugin())
        self.register(WeatherPlugin())
        self.register(WebSearchPlugin())

    def register(self, plugin: BasePlugin) -> None:
        """Register a new plugin."""
        self._plugins[plugin.name] = plugin

    def get_plugin(self, name: str) -> Optional[BasePlugin]:
        """Get a plugin by name."""
        return self._plugins.get(name)

    def list_plugins(self) -> List[BasePlugin]:
        """List all registered plugins."""
        return list(self._plugins.values())

    def match_and_run(self, message: str) -> Optional[Tuple[str, Dict[str, Any]]]:
        """
        Scan a message, match it to a plugin, extract parameters, and execute it.
        Supports both English and Arabic queries.
        
        Returns:
            Tuple of (plugin_name, result_dict) or None if no plugin matched.
        """
        message_lower = message.lower().strip()

        # 1. Translate Arabic Digits & Symbols for math
        arabic_digits = "٠١٢٣٤٥٦٧٨٩"
        english_digits = "0123456789"
        trans_table = str.maketrans(arabic_digits, english_digits)

        # Match Calculator
        math_symbols = ["+", "-", "*", "/", "×", "÷"]
        has_ops = any(op in message_lower for op in math_symbols)
        has_digits = any(d in message_lower for d in arabic_digits + english_digits)
        if "calculate" in message_lower or "احسب" in message_lower or "كم" in message_lower or (has_ops and has_digits):
            expr = message_lower.translate(trans_table).replace("×", "*").replace("÷", "/")
            expr = re.sub(r"[^\d+\-*/().\s]", "", expr).strip()
            if expr and any(c.isdigit() for c in expr):
                calc = self.get_plugin("calculator")
                if calc:
                    res = calc.execute(expression=expr)
                    if res.get("success"):
                        return calc.name, res

        # 2. Match Weather
        if any(w in message_lower for w in ["weather", "temp", "temperature", "الطقس", "حرارة", "درجة الحرارة"]):
            city = None
            city_match = re.search(r"\b(?:in|for|of|at|في|عن)\b\s+([a-zA-Z\u0600-\u06FF]+)", message_lower)
            if city_match:
                city = city_match.group(1).strip()
            if city:
                weather = self.get_plugin("weather")
                if weather:
                    return weather.name, weather.execute(location=city)

        # 3. Match Web Search
        if any(s in message_lower for s in ["search", "look up", "find info", "ابحث", "البحث", "بحث"]):
            query = None
            query_match = re.search(r"(?:search|look up|find info|ابحث عن|البحث عن|بحث)\s+(?:for|on|about|to|عن)?\s*(.+)", message_lower)
            if query_match:
                query = query_match.group(1).strip()
            else:
                query = message_lower.replace("ابحث عن", "").replace("البحث عن", "").replace("ابحث", "").replace("بحث", "").strip()
            if query:
                search = self.get_plugin("web_search")
                if search:
                    return search.name, search.execute(query=query)

        return None

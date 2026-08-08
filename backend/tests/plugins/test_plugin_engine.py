import pytest
from app.plugins.registry import PluginRegistry
from app.plugins.calculator import CalculatorPlugin
from app.plugins.weather import WeatherPlugin
from app.plugins.web_search import WebSearchPlugin


class TestPluginEngine:
    """Test cases for Plugin Engine components."""

    def test_calculator_plugin_success(self):
        plugin = CalculatorPlugin()
        result = plugin.execute(expression="2 + 2 * 3")
        assert result["success"] is True
        assert result["result"] == "8"

    def test_calculator_plugin_invalid(self):
        plugin = CalculatorPlugin()
        result = plugin.execute(expression="invalid_input")
        assert result["success"] is False
        assert "error" in result

    def test_weather_plugin_success(self):
        plugin = WeatherPlugin()
        result = plugin.execute(location="Paris")
        assert result["success"] is True
        assert result["location"] == "Paris"
        assert "Partly cloudy" in result["condition"]

    def test_web_search_plugin_success(self):
        plugin = WebSearchPlugin()
        result = plugin.execute(query="Python language")
        assert result["success"] is True
        assert len(result["results"]) > 0
        assert "python" in result["results"][0]["title"].lower()

    def test_registry_matching(self):
        registry = PluginRegistry()

        # Test calculator match
        match = registry.match_and_run("Please calculate 10 - 4")
        assert match is not None
        assert match[0] == "calculator"
        assert match[1]["result"] == "6"

        # Test weather match
        match = registry.match_and_run("What is the weather in Rome today?")
        assert match is not None
        assert match[0] == "weather"
        assert match[1]["location"] == "rome"

        # Test web search match
        match = registry.match_and_run("Search for Flutter documentation")
        assert match is not None
        assert match[0] == "web_search"
        assert len(match[1]["results"]) > 0

from typing import Any, Dict
from app.plugins.base import BasePlugin


class WeatherPlugin(BasePlugin):
    """
    Weather plugin for looking up temperature and weather status of cities.
    """

    @property
    def name(self) -> str:
        return "weather"

    @property
    def description(self) -> str:
        return "Get weather information for a specific location."

    def execute(self, location: str, **kwargs: Any) -> Dict[str, Any]:
        """
        Execute weather lookup (mock data for demo/testing).
        """
        loc_clean = location.strip().lower()
        if not loc_clean:
            return {"success": False, "error": "Location parameter is required."}

        # Mock database of weather data
        weather_db = {
            "london": {"temp": "15°C", "condition": "Cloudy with light drizzle", "humidity": "82%"},
            "paris": {"temp": "18°C", "condition": "Partly cloudy", "humidity": "65%"},
            "new york": {"temp": "22°C", "condition": "Sunny", "humidity": "50%"},
            "rome": {"temp": "26°C", "condition": "Clear and hot", "humidity": "40%"},
            "tokyo": {"temp": "20°C", "condition": "Rainy", "humidity": "90%"},
            "sydney": {"temp": "24°C", "condition": "Windy", "humidity": "55%"},
        }

        data = weather_db.get(loc_clean, {"temp": "21°C", "condition": "Sunny with light breeze", "humidity": "45%"})
        return {
            "success": True,
            "location": location,
            "temperature": data["temp"],
            "condition": data["condition"],
            "humidity": data["humidity"]
        }

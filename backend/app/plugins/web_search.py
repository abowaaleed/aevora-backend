from typing import Any, Dict
from app.plugins.base import BasePlugin


class WebSearchPlugin(BasePlugin):
    """
    Web search plugin simulating search results for query terms.
    """

    @property
    def name(self) -> str:
        return "web_search"

    @property
    def description(self) -> str:
        return "Search the web for information."

    def execute(self, query: str, **kwargs: Any) -> Dict[str, Any]:
        """
        Execute web search simulation.
        """
        query_clean = query.strip().lower()
        if not query_clean:
            return {"success": False, "error": "Query parameter is required."}

        # Mock results based on query matches
        results = []
        if "python" in query_clean:
            results.append({
                "title": "Python Programming Language - Official Website",
                "url": "https://www.python.org",
                "snippet": "Python is a programming language that lets you work quickly and integrate systems more effectively."
            })
        if "flutter" in query_clean:
            results.append({
                "title": "Flutter - Build apps for any screen",
                "url": "https://flutter.dev",
                "snippet": "Flutter transforms the app development process. Build, test, and deploy beautiful mobile, web, desktop, and embedded apps."
            })
        
        # Default mock search result if no specific terms matched
        if not results:
            results.append({
                "title": f"Search results for '{query}'",
                "url": f"https://www.google.com/search?q={query}",
                "snippet": f"Found simulated information related to '{query}'. This is a mock result from the Aevora search engine."
            })

        return {
            "success": True,
            "query": query,
            "results": results
        }

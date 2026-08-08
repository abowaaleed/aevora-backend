from fastapi import APIRouter
from app.plugins.registry import PluginRegistry


router = APIRouter()
registry = PluginRegistry()


@router.get("/")
async def list_plugins():
    """List all available plugins and their metadata."""
    plugins = registry.list_plugins()
    return [
        {
            "name": p.name,
            "description": p.description,
        }
        for p in plugins
    ]


@router.post("/execute")
async def execute_plugin(name: str, args: dict):
    """Directly execute a plugin by name."""
    plugin = registry.get_plugin(name)
    if not plugin:
        return {"success": False, "error": f"Plugin '{name}' not found."}
    
    try:
        res = plugin.execute(**args)
        return res
    except Exception as e:
        return {"success": False, "error": str(e)}

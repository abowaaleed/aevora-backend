import re
from ..task import Stage
from ..types import PipelineContext, StageStatus
from app.plugins.registry import PluginRegistry


class LoadPluginsStage(Stage):
    """
    Stage for executing plugins matching the user request.
    """
    
    def __init__(self):
        """Initialize the load plugins stage."""
        super().__init__("load_plugins")
        self.registry = PluginRegistry()
    
    def execute(self, context: PipelineContext):
        """
        Execute plugin matching and running based on the user request.
        
        Args:
            context: The pipeline context
            
        Returns:
            StageResult indicating completion or skipped status
        """
        # Determine if plugins are needed
        need_plugins = True
        required_tools = []
        if context.adaptive_decision is not None:
            need_plugins = context.adaptive_decision.need_plugins
            required_tools = context.adaptive_decision.required_tools or []

        if not need_plugins and not required_tools:
            context.plugins = None
            context.plugins_data = None
            return self._create_result(
                status=StageStatus.SKIPPED,
                output="Plugins not needed for this request"
            )

        # 1. Run tools requested by the Planner (required_tools)
        plugin_outputs = []
        for tool_name in required_tools:
            plugin = self.registry.get_plugin(tool_name)
            if not plugin:
                continue
            
            # Execute tool with context-aware parameters
            result = None
            if tool_name == "weather":
                # Check context entities for location/destination
                entities = (context.session_state or {}).get("entities", {})
                location = entities.get("destination") or entities.get("city") or entities.get("location")
                if not location:
                    # Fallback to regex match
                    city_match = re.search(r"\b(?:in|for|of|at|في|عن)\b\s+([a-zA-Z\u0600-\u06FF]+)", context.request.user_message.lower())
                    if city_match:
                        location = city_match.group(1).strip()
                if location:
                    result = plugin.execute(location=location)
                    
            elif tool_name == "calculator":
                arabic_digits = "٠١٢٣٤٥٦٧٨٩"
                english_digits = "0123456789"
                trans_table = str.maketrans(arabic_digits, english_digits)
                expr = context.request.user_message.lower().translate(trans_table).replace("×", "*").replace("÷", "/")
                expr = re.sub(r"[^\d+\-*/().\s]", "", expr).strip()
                if expr and any(c.isdigit() for c in expr):
                    result = plugin.execute(expression=expr)
                    
            elif tool_name == "web_search":
                query = context.request.user_message
                result = plugin.execute(query=query)
                
            if result and result.get("success"):
                plugin_outputs.append(f"Plugin '{tool_name}' execution result: {str(result)}")
                context.plugins = tool_name
                
        # 2. Fallback to classic matching if no outputs from required tools
        if not plugin_outputs:
            matched = self.registry.match_and_run(context.request.user_message)
            if matched:
                plugin_name, result = matched
                context.plugins = plugin_name
                plugin_outputs.append(f"Plugin '{plugin_name}' execution result: {str(result)}")

        if plugin_outputs:
            formatted_data = "\n".join(plugin_outputs)
            context.plugins_data = formatted_data
            return self._create_result(
                status=StageStatus.COMPLETED,
                output=formatted_data
            )
            
        context.plugins = None
        context.plugins_data = None
        return self._create_result(
            status=StageStatus.SKIPPED,
            output="No matching plugin execution succeeded"
        )

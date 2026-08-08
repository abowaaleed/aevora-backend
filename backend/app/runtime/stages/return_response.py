"""
Return Response Stage.

This stage finalizes the response and ensures it's ready to return.
It performs any final processing before the response is sent back.
"""

from ..task import Stage
from ..types import PipelineContext, StageStatus


class ReturnResponseStage(Stage):
    """
    Stage for finalizing and returning the response.
    
    This stage performs any final processing on the AI response before
    it's returned to the user. For Sprint 2, it simply validates that
    a response exists.
    """
    
    def __init__(self):
        """Initialize the return response stage."""
        super().__init__("return_response")
    
    def execute(self, context: PipelineContext):
        """
        Execute response finalization.
        
        Args:
            context: The pipeline context
            
        Returns:
            StageResult with the finalized response
        """
        # Validate that a response exists
        if context.ai_response is None:
            return self._create_result(
                status=StageStatus.FAILED,
                error="No AI response generated"
            )

        # Final safety cleanup for any internal tags that leaked
        import re
        context.ai_response = re.sub(r'\[SYSTEM:.*?\]', '', context.ai_response).strip()
        context.ai_response = re.sub(r'\[MISTAKE_DETECTED:.*?\]', '', context.ai_response).strip()
        context.ai_response = re.sub(r'METADATA:?.*?\s*\{.*?\}', '', context.ai_response, flags=re.DOTALL).strip()

        # Save to history
        try:
            user_id = context.request.user_id or "default"
            session_id = context.request.session_id or "default_session"
            from app.runtime.stages.build_prompt import load_history, save_history
            history = load_history(user_id, session_id)
            history.append({"role": "user", "content": context.request.user_message})
            history.append({"role": "assistant", "content": context.ai_response})
            save_history(user_id, history, session_id)
        except Exception:
            pass
        
        return self._create_result(
            status=StageStatus.COMPLETED,
            output=context.ai_response
        )

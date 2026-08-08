"""
Load Memory Stage.

This stage loads relevant memory for the current request.
"""

from ..task import Stage
from ..types import PipelineContext, StageStatus
from app.memory.service import MemoryService


class LoadMemoryStage(Stage):
    """
    Stage for retrieving relevant memories based on the user's request.
    """
    
    def __init__(self, service: MemoryService):
        """Initialize the load memory stage."""
        super().__init__("load_memory")
        self.service = service
    
    def execute(self, context: PipelineContext):
        """
        Execute memory loading.
        
        Args:
            context: The pipeline context
            
        Returns:
            StageResult indicating completion or skipped status
        """
        need_memory = True
        if context.adaptive_decision is not None:
            need_memory = context.adaptive_decision.need_memory
            
        # Overrule need_memory if the message contains potential profile/memory keywords
        msg_lower = context.request.user_message.lower()
        memory_keywords = ["name", "اسم", "who am i", "من أنا", "من انا", "live", "عيش", "أعيش", "اعيش", "مدينة", "سكن", "المدينة", "club", "team", "نادي", "فريق", "أشجع", "اشجع", "أحب", "احب", "من أين", "من اين", "شجع", "تشجع", "أين", "اين", "أحب", "القصيم"]
        if not need_memory and any(w in msg_lower for w in memory_keywords):
            need_memory = True
            
        if not need_memory:
            context.memory = None
            print(f"[TRACE] Memory Injected Into Prompt: {context.memory}\n")
            return self._create_result(
                status=StageStatus.SKIPPED,
                output="Memory not required for this request"
            )
            
        user_id = context.request.user_id or "default"
        session_id = context.request.session_id or "default_session"
        
        # Load conversation history
        from app.runtime.stages.build_prompt import load_history
        history = load_history(user_id, session_id)
        
        # Memory Before Tracing
        memories_before = self.service.get_memories(user_id)
        print(f"\n==================== [TRACE] Memory Before (User: {user_id}) ====================")
        if memories_before:
            for m in memories_before:
                print(f"  - Category: {m.category}, Subject: {m.subject}, Value: {m.value}, Content: '{m.content}'")
        else:
            print("  (No memories stored yet)")
        print("=" * 80)
        
        # Call resolve_memory
        best_memory, confidence, reason, clarification = self.service.resolve_memory(
            user_id, context.request.user_message, history
        )
        
        print(f"\n[TRACE] Memory Retrieved: {best_memory.content if best_memory else 'None'} (Confidence: {confidence:.2f}, Reason: '{reason}')")
        
        # Populate context with resolver metadata for STEP 8
        context.detected_intent = "memory_lookup" if (confidence > 0.0 or clarification) else "other"
        
        memories = self.service.get_memories(user_id)
        if best_memory:
            # Retrieved memories in same category
            retrieved = [
                m.content for m in memories
                if m.category == best_memory.category and m.subject == best_memory.subject
            ]
            if not retrieved:
                retrieved = [best_memory.content]
                
            context.memory_category = best_memory.category
            context.retrieved_memories = retrieved
            context.ranking_score = confidence * 3.0
            context.selected_memory = best_memory.content
            context.memory_confidence = confidence
            context.memory_reason = reason
        else:
            context.memory_category = None
            context.retrieved_memories = []
            context.ranking_score = 0.0
            context.selected_memory = None
            context.memory_confidence = 0.0
            context.memory_reason = reason

        # STEP 4: If confidence is low, Ask the user / Clarification
        if clarification:
            context.ai_response = clarification
            context.memory = clarification
            print(f"[TRACE] Memory Injected Into Prompt: {context.memory}\n")
            return self._create_result(
                status=StageStatus.COMPLETED,
                output=f"Low confidence memory lookup. Clarifying with user: {clarification}"
            )

        # STEP 9: If the answer comes from memory, the LLM must receive ONLY the selected memories.
        if best_memory and confidence >= 0.5:
            context.memory = f"Stored User Memory:\n1. {best_memory.content}"
            print(f"[TRACE] Memory Injected Into Prompt: {context.memory}\n")
            return self._create_result(
                status=StageStatus.COMPLETED,
                output=f"Retrieved memory: {best_memory.content}"
            )
            
        context.memory = None
        print(f"[TRACE] Memory Injected Into Prompt: {context.memory}\n")
        return self._create_result(
            status=StageStatus.SKIPPED,
            output="No matching memories found or low confidence without clarification"
        )


"""
Load User Brain Stage.

This stage queries the dedicated User Brain service and stores the resulting
profile context for prompt personalization without coupling to the Memory Engine.
"""

from ..task import Stage
from ..types import PipelineContext, StageStatus
from app.user_brain import UserBrainService


class LoadUserBrainStage(Stage):
    """Populate context with user identity and preference context."""

    def __init__(self, service: UserBrainService):
        super().__init__("load_user_brain")
        self.service = service

    def execute(self, context: PipelineContext):
        user_id = context.request.user_id or context.request.session_id or "default"
        profile = self.service.get_or_create_profile(user_id)
        context.user_brain = profile
        context.user_brain_context = self.service.build_context_summary(profile)

        result = self._create_result(
            status=StageStatus.COMPLETED,
            output=profile.model_dump(),
        )
        return result

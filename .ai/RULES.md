# General Rules

- Never rewrite the project architecture unless explicitly requested.
- Never install new dependencies without approval.
- Never delete files unless explicitly requested.
- Never rename files without approval.
- Never move files between folders unless requested.

# Code Style

- Use clean architecture.
- Write readable code.
- Prefer composition over inheritance.
- Keep functions small.
- Avoid duplicated code.
- Use meaningful variable names.
- Never duplicate logic.
- Every feature must be replaceable.
- Every service must have one responsibility.
- Every engine must be independent.
- No circular dependencies.
- Every feature should be testable.

# Backend Rules

- Backend must use Python + FastAPI.
- Business logic must never be placed inside API endpoints.
- Separate API, Services, Models, Memory and Core.
- Every API must have Pydantic models.
- Never hardcode prompts.
- Every prompt belongs inside Prompt Engine.
- Never bypass ConversationManager.

# Flutter Rules

- Flutter is only responsible for UI.
- Business logic must remain in Backend whenever possible.
- Keep widgets small and reusable.

# AI Rules

- Ollama is the default local inference engine.
- The AI engine must be replaceable in the future.
- Never tightly couple the application with Ollama.

# Memory Rules

- Memory must be stored independently from the AI model.
- User progress must survive application restarts.
- Long-term memory and short-term memory must remain separate.

# Development Rules

Before making significant code changes:

1. Explain the plan.
2. Wait for approval if the architecture changes.
3. Then implement.

Never make large architectural decisions autonomously.

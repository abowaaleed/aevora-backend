from fastapi import FastAPI, Depends
from app.api import health, chat
from app.providers.gemini_provider import GeminiProvider
from app.services.ai_engine import AIEngine
from app.services.conversation_manager import ConversationManager
from app.prompt_engine import PromptLoader, SystemPrompt, PromptBuilder
from app.runtime import StageRegistry, Pipeline, Runtime
from app.runtime.stages import (
    RAGStage,
    BuildPromptStage,
    GenerateResponseStage,
    ReturnResponseStage,
    GroundednessCheckStage,
)

from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="مستفيد",
    description="مساعد زراعي ذكي للإجابة على الأسئلة بناءً على المستندات المرفوعة",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Dependency Injection
def get_ai_provider() -> GeminiProvider:
    return GeminiProvider()

def get_ollama_provider() -> GeminiProvider:
    return GeminiProvider()


def get_prompt_loader() -> PromptLoader:
    return PromptLoader()


def get_system_prompt(loader: PromptLoader = Depends(get_prompt_loader)) -> SystemPrompt:
    return SystemPrompt(loader=loader)


def get_prompt_builder(
    system_prompt: SystemPrompt = Depends(get_system_prompt),
) -> PromptBuilder:
    return PromptBuilder(system_prompt=system_prompt)


def get_ai_engine(provider: GeminiProvider = Depends(get_ollama_provider)) -> AIEngine:
    return AIEngine(provider=provider)


def get_stage_registry(
    prompt_builder: PromptBuilder = Depends(get_prompt_builder),
    ai_engine: AIEngine = Depends(get_ai_engine),
) -> StageRegistry:
    registry = StageRegistry()

    # Only 4 stages + 1 lightweight check
    registry.register(RAGStage())
    registry.register(BuildPromptStage(prompt_builder=prompt_builder))
    registry.register(GenerateResponseStage(ai_engine=ai_engine))
    registry.register(GroundednessCheckStage())
    registry.register(ReturnResponseStage())

    return registry


def get_pipeline(registry: StageRegistry = Depends(get_stage_registry)) -> Pipeline:
    stage_order = [
        "rag",
        "build_prompt",
        "generate_response",
        "groundedness_check",
        "return_response",
    ]
    return Pipeline(registry=registry, stage_order=stage_order)


def get_runtime(
    registry: StageRegistry = Depends(get_stage_registry),
    pipeline: Pipeline = Depends(get_pipeline),
) -> Runtime:
    return Runtime(registry=registry, pipeline=pipeline)


def get_conversation_manager(runtime: Runtime = Depends(get_runtime)) -> ConversationManager:
    return ConversationManager(runtime=runtime)


from app.api.chat import get_conversation_manager as api_get_conversation_manager
app.dependency_overrides[api_get_conversation_manager] = get_conversation_manager

from fastapi.staticfiles import StaticFiles
import os

from app.api import voice, rag

# Ensure upload directory exists
upload_dir = os.path.join(os.path.dirname(__file__), "data", "uploads")
os.makedirs(upload_dir, exist_ok=True)

# Mount static files to serve uploaded documents
app.mount("/uploads", StaticFiles(directory=upload_dir), name="uploads")

app.include_router(health.router, prefix="/health", tags=["Health"])
app.include_router(chat.router, tags=["Chat"])
app.include_router(voice.router, prefix="/voice", tags=["Voice"])
app.include_router(rag.router, prefix="/rag", tags=["RAG"])

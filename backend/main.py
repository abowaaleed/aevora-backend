from fastapi import FastAPI, Depends
from app.api import health, chat
from app.providers.smart_provider import SmartProvider
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
from app.core.user_context import (
    PUBLIC_MODE,
    derive_user_id,
    set_request_context,
)

app = FastAPI(
    title="ايفورا",
    description="مساعد ذكي للإجابة على الأسئلة بناءً على المستندات المرفوعة",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

_GUARDED_PREFIXES = ("/chat", "/rag", "/voice", "/memory", "/summarize", "/conversations", "/companion")


@app.middleware("http")
async def user_context_middleware(request, call_next):
    """Per-request user keys + user id (derived from keys), enforced in PUBLIC_MODE."""
    path = request.url.path
    # فحص CORS المسبق (OPTIONS) لا يحمل مفاتيح — يجب تركه يعبر لوسيط CORS وإلا
    # ترفض المتصفحات كل الطلبات المحمية (رفع/دردشة/صوت).
    if request.method == "OPTIONS":
        return await call_next(request)
    if path in ("/", "/health", "/docs", "/openapi.json") or path.startswith("/uploads"):
        return await call_next(request)

    gemini_key = request.headers.get("x-gemini-key") or request.headers.get("x-user-gemini-key") or None
    groq_key = request.headers.get("x-groq-key") or request.headers.get("x-user-groq-key") or None
    email = request.headers.get("x-user-email") or None
    user_id = request.headers.get("x-user-id") or None

    if not user_id:
        user_id = derive_user_id(gemini_key, groq_key) if (gemini_key or groq_key) else None

    if PUBLIC_MODE and path.startswith(_GUARDED_PREFIXES) and not (gemini_key or groq_key):
        from starlette.responses import JSONResponse
        return JSONResponse(
            status_code=400,
            content={
                "detail": "يجب إدخال مفتاح API (Gemini أو Groq) في الإعدادات قبل استخدام المساعد."
            },
        )

    set_request_context(
        user_id=user_id,
        gemini_key=gemini_key,
        groq_key=groq_key,
        email=email,
    )
    # ملاحظة: لا نعيد تعيين السياق بعد الرد لأن StreamingResponse يُستهلك لاحقاً
    # خارج نطاق الوسيط. كل طلب جديد يضبط قيماً جديدة في البداية، لذا لا تسريب.
    return await call_next(request)


# Dependency Injection
def get_ai_provider() -> SmartProvider:
    return SmartProvider()

def get_ollama_provider() -> SmartProvider:
    return SmartProvider()


def get_prompt_loader() -> PromptLoader:
    return PromptLoader()


def get_system_prompt(loader: PromptLoader = Depends(get_prompt_loader)) -> SystemPrompt:
    return SystemPrompt(loader=loader)


def get_prompt_builder(
    system_prompt: SystemPrompt = Depends(get_system_prompt),
) -> PromptBuilder:
    return PromptBuilder(system_prompt=system_prompt)


def get_ai_engine(provider: SmartProvider = Depends(get_ollama_provider)) -> AIEngine:
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

from app.api import voice, rag, companion

# Ensure upload directory exists
upload_dir = os.path.join(os.path.dirname(__file__), "data", "uploads")
os.makedirs(upload_dir, exist_ok=True)

# Mount static files to serve uploaded documents
app.mount("/uploads", StaticFiles(directory=upload_dir), name="uploads")

app.include_router(health.router, prefix="/health", tags=["Health"])
app.include_router(chat.router, tags=["Chat"])
app.include_router(voice.router, prefix="/voice", tags=["Voice"])
app.include_router(rag.router, prefix="/rag", tags=["RAG"])
app.include_router(companion.router, prefix="/companion", tags=["Companion"])

from fastapi import FastAPI
from app.api import health

app = FastAPI(
    title="AI Companion",
    description="A completely local AI companion that can run without cloud APIs",
    version="0.1.0"
)

app.include_router(health.router, tags=["Health"])

from fastapi import APIRouter, UploadFile, File, BackgroundTasks, HTTPException, Depends
from fastapi.responses import StreamingResponse
from typing import List, Dict, Any
from app.rag.document_service import DocumentService
from app.providers.gemini_provider import GeminiProvider
from app.services.smart_router import SmartRouter
import json
import os
import asyncio
from pathlib import Path

router = APIRouter()
doc_service = DocumentService()
smart_router = SmartRouter()

def get_gemini_provider() -> GeminiProvider:
    return GeminiProvider()

@router.post("/summarize")
async def summarize_document(
    file: UploadFile = File(...),
    gemini_provider: GeminiProvider = Depends(get_gemini_provider)
):
    """
    Summarize an uploaded file.
    Text is extracted locally first, then summarized via the smart router
    (Gemini primary, Groq fallback). Scanned PDFs without extractable text
    are sent to Gemini's native PDF support instead.
    """
    # Save file locally first
    temp_path = f"data/uploads/temp_{file.filename}"
    with open(temp_path, "wb") as f:
        f.write(await file.read())

    async def event_generator():
        try:
            text = ""
            ext = Path(temp_path).suffix.lower()
            try:
                if ext == ".pdf":
                    import fitz
                    doc = fitz.open(temp_path)
                    for page in doc:
                        text += page.get_text()
                elif ext == ".txt":
                    with open(temp_path, "r", encoding="utf-8", errors="ignore") as f:
                        text = f.read()
                elif ext == ".docx":
                    import docx
                    d = docx.Document(temp_path)
                    text = "\n".join(p.text for p in d.paragraphs)
            except Exception as te:
                print(f"[RAG API] Local text extraction error: {te}")

            if len(text.strip()) >= 20:
                summary = await asyncio.to_thread(smart_router.summarize_text, text)
                yield f"data: {json.dumps({'text': summary})}\n\n"
                yield "data: [DONE]\n\n"
                return

            # No extractable text (e.g. scanned PDF) — use Gemini's native PDF support.
            async for chunk in gemini_provider.service.process_pdf_and_summarize(temp_path):
                yield f"data: {json.dumps({'text': chunk})}\n\n"
            yield "data: [DONE]\n\n"
        except Exception as e:
            print(f"[RAG API] Summarization error: {e}")
            yield f"data: {json.dumps({'error': str(e)})}\n\n"
        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)

    return StreamingResponse(event_generator(), media_type="text/event-stream")

@router.post("/upload")
async def upload_documents(files: List[UploadFile] = File(...)):
    """Upload and start background indexing of documents."""
    results = []
    for file in files:
        content = await file.read()
        doc_service.start_indexing(file.filename, content)
        results.append({"filename": file.filename, "status": "queued"})
    return {"results": results}

@router.get("/files")
async def list_documents():
    """List all uploaded documents and their processing status."""
    return doc_service.list_files()

@router.get("/files/{filename}/content")
async def get_document_content(filename: str):
    """Retrieve the extracted text content of a processed document."""
    content = doc_service.get_file_content(filename)
    if content is None:
        status = doc_service.get_status(filename)
        if status == "unknown":
            raise HTTPException(status_code=404, detail=f"File '{filename}' not found")
        raise HTTPException(status_code=400, detail=f"File not ready. Status: {status}")
    return {"filename": filename, "content": content, "length": len(content)}

@router.delete("/files/{filename}")
async def delete_document(filename: str):
    """Delete an uploaded document and its indexed data."""
    success = doc_service.delete_file(filename)
    if not success:
        raise HTTPException(status_code=500, detail=f"Failed to delete '{filename}'")
    return {"deleted": filename}

@router.post("/query")
async def query_documents(query: str):
    """Query the RAG system."""
    result = doc_service.query(query)
    return result

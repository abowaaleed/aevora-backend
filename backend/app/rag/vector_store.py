import chromadb
from chromadb.api.types import EmbeddingFunction, Documents, Embeddings
from pathlib import Path
from typing import List, Dict, Any, Optional
import google.generativeai as genai
import hashlib
import json
import math
import os
import re

EMBEDDING_MODEL = "models/gemini-embedding-001"
EMBEDDING_DIM = 3072
EMBEDDING_VERSION = "evora-v2"

_MODE_FILE = Path(__file__).parent.parent.parent / "data" / "embedding_mode.json"


def _hash_embed(text: str, dim: int = EMBEDDING_DIM) -> List[float]:
    """
    Deterministic keyword-hash embedding used when the Gemini embedding API is
    unavailable (e.g. free-tier quota exhausted). Fixed dimension, normalized.
    Two texts sharing Arabic/English words get high cosine similarity, which
    keeps RAG retrieval functional even without the semantic model.
    """
    vec = [0.0] * dim
    tokens = re.findall(r'[\u0600-\u06FF]{2,}|[a-zA-Z0-9]{2,}', text.lower())
    for tok in tokens:
        grams = {tok}
        if len(tok) > 3:
            grams.update(tok[i:i + 3] for i in range(len(tok) - 2))
        for g in grams:
            h = int.from_bytes(hashlib.md5(g.encode("utf-8")).digest()[:8], "big")
            idx = h % dim
            sign = 1.0 if (h >> 7) & 1 else -1.0
            vec[idx] += sign
    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [v / norm for v in vec]


class GeminiEmbeddingFunction(EmbeddingFunction):
    """
    Custom embedding function using the Google Gemini API, with a
    deterministic keyword-hash fallback.

    If Gemini fails on the first call (quota/network), the process switches to
    hash mode for the rest of its lifetime so all vectors in a collection stay
    mutually consistent (no mixing of semantic + keyword vectors).
    """

    def __init__(self, model_name: str = EMBEDDING_MODEL):
        self.model_name = model_name
        api_key = os.getenv("GEMINI_API_KEY")
        if api_key:
            genai.configure(api_key=api_key)
        self._mode = self._load_mode()

    @staticmethod
    def _load_mode() -> str:
        try:
            return json.loads(_MODE_FILE.read_text(encoding="utf-8")).get("mode", "gemini")
        except Exception:
            return "gemini"

    @staticmethod
    def _save_mode(mode: str):
        try:
            _MODE_FILE.parent.mkdir(parents=True, exist_ok=True)
            _MODE_FILE.write_text(json.dumps({"mode": mode}), encoding="utf-8")
        except Exception as e:
            print(f"[VECTOR STORE] Could not persist embedding mode: {e}")

    def __call__(self, input: Documents) -> Embeddings:
        inputs = list(input)
        if self._mode == "gemini":
            try:
                result = genai.embed_content(
                    model=self.model_name,
                    content=inputs,
                    task_type="retrieval_document"
                )
                emb = result['embedding']
                return emb
            except Exception as e:
                print(f"[VECTOR STORE] Gemini Embedding error ({e}) — switching to keyword-hash fallback")
                self._mode = "hash"
                self._save_mode("hash")
        return [_hash_embed(t) for t in inputs]

class LocalVectorStore:
    """
    Wrapper for ChromaDB local persistent storage.
    """
    def __init__(self):
        self.persist_directory = str(Path(__file__).parent.parent.parent / "data" / "chroma")
        self.client = chromadb.PersistentClient(path=self.persist_directory)
        self.embedding_function = GeminiEmbeddingFunction()
        self.collection = self.client.get_or_create_collection(
            name="documents",
            embedding_function=self.embedding_function,
            metadata={"hnsw:space": "cosine", "embedding_version": EMBEDDING_VERSION}
        )
        # Recreate the collection if the embedding model changed (dimension mismatch).
        meta = self.collection.metadata or {}
        if meta.get("embedding_version") != EMBEDDING_VERSION:
            print(f"[VECTOR STORE] Embedding model changed — recreating collection (old={meta.get('embedding_version')}, new={EMBEDDING_VERSION})")
            try:
                self.client.delete_collection("documents")
            except Exception:
                pass
            self.collection = self.client.get_or_create_collection(
                name="documents",
                embedding_function=self.embedding_function,
                metadata={"hnsw:space": "cosine", "embedding_version": EMBEDDING_VERSION}
            )

    def add_documents(self, ids: List[str], documents: List[str], metadatas: List[Dict[str, Any]]):
        """Add chunks to the vector store."""
        self.collection.add(
            ids=ids,
            documents=documents,
            metadatas=metadatas
        )

    def search(self, query: str, limit: int = 3) -> List[Dict[str, Any]]:
        """Search for relevant chunks."""
        results = self.collection.query(
            query_texts=[query],
            n_results=limit
        )

        formatted_results = []
        if results['documents']:
            for i in range(len(results['documents'][0])):
                formatted_results.append({
                    "content": results['documents'][0][i],
                    "metadata": results['metadatas'][0][i],
                    "distance": results['distances'][0][i] if 'distances' in results else None
                })
        return formatted_results

    def delete_by_file(self, filename: str):
        """Remove all chunks associated with a file."""
        self.collection.delete(where={"filename": filename})

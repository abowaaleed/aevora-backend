import chromadb
from chromadb.api.types import EmbeddingFunction, Documents, Embeddings
from pathlib import Path
from typing import List, Dict, Any, Optional
import google.generativeai as genai
import os

import google.generativeai as genai
import os

class GeminiEmbeddingFunction(EmbeddingFunction):
    """
    Custom embedding function using Google Gemini API.
    """
    def __init__(self, model_name: str = "models/text-embedding-004"):
        self.model_name = model_name
        api_key = os.getenv("GEMINI_API_KEY")
        if api_key:
            genai.configure(api_key=api_key)

    def __call__(self, input: Documents) -> Embeddings:
        try:
            result = genai.embed_content(
                model=self.model_name,
                content=input,
                task_type="retrieval_document"
            )
            return result['embedding']
        except Exception as e:
            print(f"[VECTOR STORE] Gemini Embedding error: {e}")
            # Fallback to zero vector if embedding fails
            # text-embedding-004 is 768 dimensions
            return [[0.0] * 768 for _ in input]

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
            metadata={"hnsw:space": "cosine"}
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

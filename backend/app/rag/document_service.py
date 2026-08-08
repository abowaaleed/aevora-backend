import os
import re
import unicodedata
import fitz # PyMuPDF
import docx
import pandas as pd
import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional, Tuple
from .vector_store import LocalVectorStore
from .structured_store import StructuredStore
from .structured_extractor import extract_records, compute_answer, StructuredRecordStore, detect_range_query
from app.services.gemini_service import GeminiService
import threading
import asyncio

SMALL_DOC_THRESHOLD = 2000  # chars — documents under this size use full-injection mode
LARGE_DOC_TOP_K = 3          # chunks retrieved for large documents

# Supported image extensions — sent to Gemini vision for content extraction.
_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif", ".heic", ".heif"}

_IMAGE_MIME = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".bmp": "image/bmp",
    ".gif": "image/gif",
    ".heic": "image/heic",
    ".heif": "image/heif",
}

# ── Aggregation / counting query detection ──────────────────────────────────
# Rule-based classifier: returns True when a query demands numeric computation
# (sum, count, filter-by-range) over document data.  These CANNOT be answered
# reliably by an LLM reasoning over raw text — the only safe options are
# structured-SQL computation (path 2a) or consistent refusal (path 2b).
_AGG_COUNT_PATTERNS = [
    # "كم عدد ..."  (how many)
    r'كم\s+عدد',
    # "عدد ..." followed by quantifier
    r'عدد\s+\S+\s+(?:الذي|التي|ذوي|الذين|اللذين|اللواتي)',
    # "كم ... هناك / موجود / في"  (how many … are there / exist / in)
    r'كم\s+\S+(?:\s+\S+)*?\s+(?:هناك|موجود|في|بـ|عند)',
    # "المجموع" / "المجموع الكلي" / "اجمالي"
    r'(?:المجموع|المجموع\s+الكلي|اجمالي|الإجمالي|إجمالي)',
    # range filters: "بين X و Y" / "أكثر من" / "أقل من" / "أكبر من" / "اصغر من"
    r'بين\s+\d+\s+و\s*\d+',  # "بين X وY" (waw may or may not have space before number)
    r'(?:أكثر|اكبر|أكبر|agbar)\s+من\s+\d+',
    r'(?:أقل|اصغر|أصغر)\s+من\s+\d+',
    r'(?: فوق|اعلى|أعلى)\s+\d+',
    r'(?:تحت|ادنى|أدنى)\s+\d+',
    # "أين يقع" style is NOT aggregation — leave out
    # explicit "سنة" / "عام" age-range patterns
    r'(?:عمر|عمره|عمرها|أعمار)\s+\S+\s+(?:بين|يزيد|يقل|larger|smaller)',
    r'بين\s+\d+\s+و\s+\d+\s+(?:سنة|عام|سنه)',
]

_AGG_COUNT_RE = re.compile('|'.join(_AGG_COUNT_PATTERNS), re.IGNORECASE)


def is_aggregation_query(query: str) -> bool:
    """Detect whether a user query requires numeric aggregation over document data."""
    return bool(_AGG_COUNT_RE.search(query))


def is_single_fact_lookup(query: str) -> bool:
    """
    CASE A: Detect single-fact lookups that should bypass aggregation detection.
    These are queries like "كم عدد السماعات في الدرج 2" where the answer is a
    single explicit number stated in the document, not a computation.
    """
    # If the query mentions a specific location (درج N, غرفة N), it's a lookup
    if re.search(r'(?:الدرج|درج)\s+(?:رقم\s*)?\d+', query):
        return True
    if re.search(r'غرفة\s+\S+', query):
        return True
    # If the query asks about a specific item type in a specific drawer/room
    # "عدد السماعات في الدرج 2" → lookup, but "عدد الموظفين في بيت الربوة" → aggregation
    if re.search(r'عدد\s+\S+\s+في\s+(?:الدرج|درج|غرفة)', query):
        return True
    return False


def is_list_enumerate_query(query: str) -> bool:
    """
    Detect queries that ask to list/enumerate items from structured data.
    These should be routed to compute_answer for deterministic output,
    not left to the LLM which garbles lists from raw text.
    """
    _LIST_PATTERNS = [
        r'اذكر\s+(?:الملفات|الملف|جميع|كل)',
        r'اذكرها',
        r'اين\s+(?:هي|هم)',
        r'ما\s+(?:هي|هو)\s+(?:الملفات|الملف|المحتويات)',
        r'اين\s+(?:توجد|يوجد|تقع|يقع)',
        r'(?:列举|list\s+all)',
    ]
    return bool(re.search('|'.join(_LIST_PATTERNS), query, re.IGNORECASE))


def _split_into_sections(text: str) -> list[tuple[str, str]]:
    """
    Split document text into (header, body) sections based on Arabic heading patterns.
    A heading is a line that:
    - Ends with ':' or ' :' or ' :'
    - Is short (< 80 chars)
    - Is followed by a newline
    
    Returns list of (header, body) tuples. The first section may have empty header (preamble).
    """
    lines = text.split('\n')
    sections = []
    current_header = ""
    current_body_lines = []

    for line in lines:
        stripped = line.strip()
        # Detect heading: short line ending with ':' (with optional spaces before)
        is_heading = (
            stripped.endswith(':') or stripped.endswith(' :') or stripped.endswith(' :')
        ) and len(stripped) < 80 and len(stripped) > 2

        if is_heading:
            # Save previous section
            if current_header or current_body_lines:
                body = '\n'.join(current_body_lines).strip()
                sections.append((current_header, body))
            current_header = stripped.rstrip(':').strip()
            current_body_lines = []
        else:
            current_body_lines.append(line)

    # Save last section
    if current_header or current_body_lines:
        body = '\n'.join(current_body_lines).strip()
        sections.append((current_header, body))

    return sections


def _score_section_relevance(header: str, body: str, query: str) -> float:
    """
    Score how relevant a section is to the query based on keyword overlap.
    Uses simple word matching — no LLM call needed.
    """
    query_words = set(re.findall(r'[\u0600-\u06FF]{3,}', query.lower()))
    if not query_words:
        return 0.0

    header_text = header.lower()
    body_text = body.lower()
    full_text = header_text + " " + body_text

    # Score: header matches count more than body matches
    header_matches = sum(1 for w in query_words if w in header_text)
    body_matches = sum(1 for w in query_words if w in body_text)

    # Weight: header matches are 3x more important
    score = (header_matches * 3.0 + body_matches * 1.0) / len(query_words)
    return score


def _score_doc_relevance(full_text: str, query: str) -> float:
    """
    Score how relevant an entire document is to the query based on keyword
    overlap. Weights query-word matches by length so rarer (more specific)
    terms such as 'السجل التجاري' dominate over common filler words.
    """
    query_words = set(re.findall(r'[\u0600-\u06FF]{3,}', query.lower()))
    if not query_words:
        return 0.0
    text = full_text.lower()
    total = 0.0
    for w in query_words:
        if w in text:
            total += 1.0 + min(len(w) / 20.0, 1.0)
    return total / len(query_words)


class DocumentService:
    """
    Main service for document processing and RAG operations.
    """
    def __init__(self):
        self.vector_store = LocalVectorStore()
        self.structured_store = StructuredStore()
        self.record_store = StructuredRecordStore()  # structured records from text extraction
        self.upload_dir = Path(__file__).parent.parent.parent / "data" / "uploads"
        self.upload_dir.mkdir(parents=True, exist_ok=True)
        self._processing_status = {} # filename -> status (pending, processing, indexed, failed)
        self._processing_progress = {} # filename -> percentage/details
        self._rebuild_status_from_stores()
        self._rebuild_structured_records()

    def get_status(self, filename: str) -> str:
        return self._processing_status.get(filename, "unknown")

    def _rebuild_status_from_stores(self):
        """Rebuild processing status from existing vector store data on startup."""
        try:
            # Get all unique filenames from the vector store
            results = self.vector_store.collection.get(include=["metadatas"])
            if results and results.get("metadatas"):
                filenames = set()
                for meta in results["metadatas"]:
                    if isinstance(meta, dict) and "filename" in meta:
                        filenames.add(meta["filename"])
                for fname in filenames:
                    if fname not in self._processing_status:
                        self._processing_status[fname] = "indexed"
                        self._processing_progress[fname] = "Restored from vector store"
        except Exception as e:
            print(f"[DOCUMENT SERVICE] Could not rebuild status from stores: {e}")

    def _rebuild_structured_records(self):
        """Rebuild structured records from existing vector store documents on startup."""
        if self.record_store.get_files_with_records():
            print(f"[DOCUMENT SERVICE] Structured records already loaded: {len(self.record_store.get_files_with_records())} files")
            return
        # Re-extract from all indexed documents
        try:
            results = self.vector_store.collection.get(include=["documents", "metadatas"])
            if not results or not results.get("documents"):
                return
            # Group documents by filename
            docs_by_file: Dict[str, str] = {}
            for doc, meta in zip(results["documents"], results["metadatas"]):
                fname = meta.get("filename", "") if isinstance(meta, dict) else ""
                if fname:
                    if fname not in docs_by_file:
                        docs_by_file[fname] = ""
                    docs_by_file[fname] += doc + "\n"
            for fname, full_text in docs_by_file.items():
                records = extract_records(full_text, fname)
                if records:
                    self.record_store.store(fname, records)
                    print(f"[DOCUMENT SERVICE] Extracted {len(records)} structured records from {fname}")
        except Exception as e:
            print(f"[DOCUMENT SERVICE] Could not rebuild structured records: {e}")

    def list_files(self) -> List[Dict[str, Any]]:
        files = []
        # Rebuild from vector store to catch any files not in memory
        seen = set()
        for fname, status in self._processing_status.items():
            files.append({
                "filename": fname,
                "status": status,
                "progress": self._processing_progress.get(fname, "")
            })
            seen.add(fname)
        # Also include files in vector store but not in memory (from previous sessions)
        try:
            results = self.vector_store.collection.get(include=["metadatas"])
            if results and results.get("metadatas"):
                for meta in results["metadatas"]:
                    fname = meta.get("filename") if isinstance(meta, dict) else None
                    if fname and fname not in seen:
                        files.append({
                            "filename": fname,
                            "status": "indexed",
                            "progress": "Restored from vector store"
                        })
                        seen.add(fname)
        except Exception:
            pass
        return files

    def start_indexing(self, filename: str, content: bytes):
        """Start background indexing task."""
        file_path = self.upload_dir / filename
        with open(file_path, "wb") as f:
            f.write(content)

        self._processing_status[filename] = "pending"
        # Run indexing in a separate thread
        thread = threading.Thread(target=self._process_file, args=(filename,))
        thread.start()

    def _process_file(self, filename: str):
        try:
            self._processing_status[filename] = "processing"
            file_path = self.upload_dir / filename
            ext = file_path.suffix.lower()

            if ext in [".xlsx", ".xls", ".csv"]:
                # Structured data
                self._processing_progress[filename] = "Parsing tabular data..."
                if ext == ".csv":
                    df = pd.read_csv(file_path)
                else:
                    df = pd.read_excel(file_path)

                self.structured_store.load_file(filename, df)
                self._processing_status[filename] = "indexed"
                self._processing_progress[filename] = f"Loaded {len(df)} rows."

            elif ext in [".pdf", ".docx", ".txt"]:
                # Unstructured text
                self._processing_progress[filename] = "Extracting text..."
                text = ""
                if ext == ".pdf":
                    doc = fitz.open(file_path)
                    for page in doc:
                        text += page.get_text()
                elif ext == ".docx":
                    doc = docx.Document(file_path)
                    text = "\n".join([para.text for para in doc.paragraphs])
                else:
                    with open(file_path, "r", encoding="utf-8") as f:
                        text = f.read()

                # Normalize Unicode: convert Presentation Forms (FB/FE) to logical Arabic (06xx)
                text = unicodedata.normalize('NFKC', text)

                # Scanned PDF fallback: if text extraction returned nothing useful,
                # send the PDF to Gemini for full analysis and content extraction.
                if ext == ".pdf" and len(text.strip()) < 20:
                    self._processing_progress[filename] = "Scanned PDF — analyzing with Gemini..."
                    try:
                        gemini_text = GeminiService().extract_text_from_pdf(str(file_path))
                        if gemini_text:
                            text = gemini_text
                    except Exception as ge:
                        print(f"[DOCUMENT SERVICE] Gemini PDF extraction failed for {filename}: {ge}")

                self._index_text(filename, text)

            elif ext in _IMAGE_EXTS:
                # Images — send to Gemini vision for content extraction, then index the text
                self._processing_progress[filename] = "Analyzing image with Gemini..."
                try:
                    image_bytes = file_path.read_bytes()
                    mime = _IMAGE_MIME.get(ext, "image/jpeg")
                    text = GeminiService().extract_text_from_image(image_bytes, mime)
                except Exception as e:
                    print(f"[DOCUMENT SERVICE] Image extraction error for {filename}: {e}")
                    self._processing_status[filename] = "failed"
                    self._processing_progress[filename] = f"فشل تحليل الصورة: {e}"
                    return

                if not text.strip():
                    self._processing_status[filename] = "failed"
                    self._processing_progress[filename] = "لم يستطع النموذج استخراج محتوى من هذه الصورة."
                    return

                self._index_text(filename, text)

            else:
                self._processing_status[filename] = "failed"
                self._processing_progress[filename] = "Unsupported file format."
        except Exception as e:
            print(f"[DOCUMENT SERVICE] Processing error for {filename}: {e}")
            self._processing_status[filename] = "failed"
            self._processing_progress[filename] = str(e)

    def _index_text(self, filename: str, text: str):
        """
        Index extracted text into the vector store.
        Small documents use full-injection; large documents are chunked.
        Also extracts structured records for aggregation queries.
        """
        is_small = len(text) <= SMALL_DOC_THRESHOLD

        if is_small:
            self._processing_progress[filename] = "Small document — storing full text for direct injection..."
            docs = [text]
            metadatas = [{
                "filename": filename,
                "clause": "",
                "index": 0,
                "mode": "full_injection",
                "char_count": len(text),
                "timestamp": datetime.datetime.now().isoformat()
            }]
            ids = [f"{filename}_full"]
        else:
            self._processing_progress[filename] = "Chunking text..."
            chunks = self._chunk_text(text)
            self._processing_progress[filename] = f"Generating embeddings (0/{len(chunks)})..."
            ids = []
            docs = []
            metadatas = []

            for i, chunk_data in enumerate(chunks):
                chunk_text, clause_num = chunk_data
                cid = f"{filename}_{i}"
                ids.append(cid)
                docs.append(chunk_text)
                metadatas.append({
                    "filename": filename,
                    "clause": clause_num or "",
                    "index": i,
                    "mode": "chunked",
                    "timestamp": datetime.datetime.now().isoformat()
                })
                if (i + 1) % 5 == 0 or i == len(chunks) - 1:
                    self._processing_progress[filename] = f"Generating embeddings ({i+1}/{len(chunks)})..."

        self.vector_store.add_documents(ids, docs, metadatas)
        self._processing_status[filename] = "indexed"
        mode_label = "full-injection (small)" if is_small else f"chunked ({len(docs)} chunks)"
        self._processing_progress[filename] = f"Indexed: {mode_label}."

        # Extract structured records from text (for aggregation queries)
        records = extract_records(text, filename)
        if records:
            self.record_store.store(filename, records)
            print(f"[DOCUMENT SERVICE] Extracted {len(records)} structured records from {filename}")

    def _chunk_text(self, text: str) -> List[Tuple[str, Optional[str]]]:
        """
        Intelligent chunking based on clause boundaries.
        Returns List of (chunk_text, clause_number).
        """
        # Patterns for clause/article boundaries in Arabic and English
        # e.g. "البند 203", "المادة 5", "Clause 10", "Article 2.1"
        patterns = [
            r'(?:البند|المادة|الفقرة|Clause|Article|Section)\s*(\d+(?:\.\d+)*)',
        ]

        combined_pattern = '|'.join(patterns)
        splits = re.split(combined_pattern, text)

        chunks = []
        # re.split with groups returns matches as well.
        # Format: [text_before, match1, text_between, match2, ...]

        # If no matches found, use simple paragraph splitting
        if len(splits) == 1:
            return self._chunk_by_paragraphs(text)

        # First part might be a preamble
        if splits[0].strip():
            chunks.append((splits[0].strip(), None))

        for i in range(1, len(splits), 2):
            clause_num = splits[i]
            content = splits[i+1].strip() if i+1 < len(splits) else ""
            # Prepend the clause header to content for context
            full_content = f"Clause {clause_num}: {content}"
            chunks.append((full_content, clause_num))

        return chunks

    def _chunk_by_paragraphs(self, text: str) -> List[Tuple[str, Optional[str]]]:
        """
        Split text into reasonably-sized chunks. PDF extraction often produces a
        newline per line (no blank paragraphs), so we fall back to accumulating
        lines up to a target size with overlap — never one giant chunk.
        """
        TARGET = 900
        OVERLAP = 150
        paragraphs = [p for p in (p.strip() for p in text.split("\n")) if p]
        if not paragraphs:
            return []

        chunks: List[Tuple[str, Optional[str]]] = []
        current = ""
        for para in paragraphs:
            if not current:
                current = para
            elif len(current) + len(para) + 1 <= TARGET:
                current += "\n" + para
            else:
                chunks.append((current, None))
                # overlap: carry the tail of the previous chunk so numbers
                # spanning chunk boundaries aren't lost
                tail = current[-OVERLAP:] if len(current) > OVERLAP else ""
                current = (tail + "\n" + para) if tail else para
        if current:
            chunks.append((current, None))
        return chunks

    def get_file_content(self, filename: str) -> Optional[str]:
        """Retrieve the extracted text content of a processed file."""
        # Try the vector store directly — don't depend solely on in-memory status
        try:
            results = self.vector_store.collection.get(
                where={"filename": filename},
                include=["documents", "metadatas"]
            )
            if not results or not results.get("documents"):
                return None
            docs = results["documents"]
            metas = results.get("metadatas") or [{}] * len(docs)
            indexed = []
            for doc, meta in zip(docs, metas):
                idx = meta.get("index", 0) if isinstance(meta, dict) else 0
                indexed.append((idx, doc))
            indexed.sort(key=lambda x: x[0])
            return "\n\n".join(text for _, text in indexed)
        except Exception as e:
            print(f"[DOCUMENT SERVICE] Error getting content for {filename}: {e}")
            return None

    def delete_file(self, filename: str) -> bool:
        """Delete a file and its indexed data."""
        try:
            # Remove from vector store
            self.vector_store.delete_by_file(filename)
            # Remove from structured store
            self.structured_store.delete_file(filename)
            # Remove from structured records
            self.record_store.delete(filename)
            # Remove from disk
            file_path = self.upload_dir / filename
            if file_path.exists():
                file_path.unlink()
            # Remove from status tracking
            self._processing_status.pop(filename, None)
            self._processing_progress.pop(filename, None)
            return True
        except Exception as e:
            print(f"[DOCUMENT SERVICE] Error deleting {filename}: {e}")
            return False

    def query(self, user_query: str) -> Dict[str, Any]:
        """
        Execute RAG query with routing logic.
        Small documents use full-injection; large documents use chunked retrieval.
        Aggregation/counting queries against unstructured text are refused safely.
        CASE A (single-fact lookup) bypasses aggregation detection.
        CASE B (true aggregation) uses structured records if available.
        """
        # 0. CASE A: Single-fact lookup — bypass aggregation detection entirely.
        #    These queries ask for a specific stated number, not a computation.
        if is_single_fact_lookup(user_query) and is_aggregation_query(user_query):
            print(f"[RAG] Single-fact lookup detected (CASE A): '{user_query}'")
            # Try structured records first for accurate answer
            all_records = []
            for fname in self.record_store.get_files_with_records():
                all_records.extend(self.record_store.get_records(fname))
            if all_records:
                answer = compute_answer(all_records, user_query)
                if answer:
                    print(f"[RAG] CASE A: answered from structured records")
                    return {
                        "type": "structured_answer",
                        "answer": answer,
                        "sources": list(set(r.get("source_file", "") for r in all_records)),
                    }
            # Fall through to normal RAG text-retrieval (the number is stated in the text)

        # 0a. CASE D: Range-lookup — deterministic interval matching for quota tables.
        #     e.g. "عندي 15 رأس غنم، كم عامل يحق لي؟" → checks parsed range table.
        range_query = detect_range_query(user_query)
        if range_query:
            print(f"[RAG] Range-lookup detected (CASE D): value={range_query['value']}, "
                  f"unit={range_query.get('unit_hint')}, category={range_query.get('category_hint')}")
            all_records = []
            for fname in self.record_store.get_files_with_records():
                all_records.extend(self.record_store.get_records(fname))
            if all_records:
                answer = compute_answer(all_records, user_query)
                if answer:
                    print(f"[RAG] CASE D: answered from range-lookup records")
                    return {
                        "type": "structured_answer",
                        "answer": answer,
                        "sources": list(set(r.get("source_file", "") for r in all_records)),
                    }
            # No range records — fall through to aggregation check

        # 0b. CASE B: True aggregation — use structured records if available
        if is_aggregation_query(user_query):
            print(f"[RAG] Aggregation query detected: '{user_query}'")
            # Try structured records first
            all_records = []
            for fname in self.record_store.get_files_with_records():
                all_records.extend(self.record_store.get_records(fname))
            if all_records:
                answer = compute_answer(all_records, user_query)
                if answer:
                    print(f"[RAG] CASE B: answered from structured records")
                    return {
                        "type": "structured_answer",
                        "answer": answer,
                        "sources": list(set(r.get("source_file", "") for r in all_records)),
                    }
            # No structured records or couldn't compute — fall back to Path 2b
            # Check if we have structured (tabular) data from xlsx/csv
            tables = self.structured_store.get_table_info()
            if tables:
                # Structured path (path 2a for xlsx/csv) — let it through to SQL routing below
                print("[RAG] Structured tables available — routing to structured query path")
            else:
                # No structured data — let the LLM try to answer from RAG context.
                # The quota table / range data may be in the document text.
                # Groundedness check will catch hallucinated answers.
                print("[RAG] No structured tables — falling through to text-based RAG for aggregation")

        # 0c. CASE C: List/enumerate queries — route to structured extraction for deterministic output.
        #     These ask to list items (files, inventory, etc.) from a specific location.
        #     The LLM garbles lists from raw text, so we use compute_answer instead.
        if is_list_enumerate_query(user_query):
            print(f"[RAG] List/enumerate query detected (CASE C): '{user_query}'")
            all_records = []
            for fname in self.record_store.get_files_with_records():
                all_records.extend(self.record_store.get_records(fname))
            if all_records:
                answer = compute_answer(all_records, user_query)
                if answer:
                    print(f"[RAG] CASE C: answered from structured records")
                    return {
                        "type": "structured_answer",
                        "answer": answer,
                        "sources": list(set(r.get("source_file", "") for r in all_records)),
                    }
            # Fall through to full-injection if structured records couldn't answer

        # 1. Check for small (full-injection) documents first
        small_docs = self._get_small_doc_contents()
        if small_docs:
            print(f"[RAG] Found {len(small_docs)} small document(s) for full injection")

            combined_answer = ""
            sources = []
            # If the query has no Arabic words to score with, inject the full
            # document text (can't rank by keyword overlap).
            query_arabic_words = set(re.findall(r'[\u0600-\u06FF]{3,}', user_query.lower()))

            if not query_arabic_words:
                # English / numeric queries — inject every small document in full
                for fname, full_text in small_docs.items():
                    combined_answer += f"[المستند: {fname}]\n{full_text}\n\n"
                    sources.append(fname)
            else:
                # Arabic queries — rank documents by keyword overlap, then inject
                # the best-matching document IN FULL (small docs fit the prompt).
                # Injecting the entire document prevents false "not found" answers
                # that section-trimming caused when the relevant fact sat in a
                # section whose header scored low against the query.
                scored = []
                for fname, full_text in small_docs.items():
                    score = _score_doc_relevance(full_text, user_query)
                    scored.append((score, fname, full_text))
                scored.sort(key=lambda x: x[0], reverse=True)
                # Always inject at least the top document so a relevant fact is
                # never dropped just because scoring was conservative.
                for rank, (score, fname, full_text) in enumerate(scored[:2]):
                    combined_answer += f"[المستند: {fname}]\n{full_text}\n\n"
                    sources.append(fname)
                    print(f"[RAG] Injected full small document {fname} (rank {rank + 1}, score {score:.2f})")

            # Also add large doc chunks if relevant
            large_results = self.vector_store.search(user_query, limit=LARGE_DOC_TOP_K)
            large_results = [r for r in large_results if r['metadata'].get('mode') != 'full_injection']
            if large_results:
                combined_answer += "Additional context from larger documents:\n"
                for res in large_results:
                    combined_answer += f"- {res['content']}\n"
                    fn = res['metadata'].get('filename', '')
                    if fn not in sources:
                        sources.append(fn)

            if combined_answer.strip():
                return {
                    "type": "full_injection",
                    "answer": combined_answer.strip(),
                    "sources": sources
                }
            # Nothing relevant was injected — fall through to the other retrieval paths.

        # 1. Check for explicit clause number (Fix for "البند 203")
        clause_match = re.search(r'(?:البند|المادة|الفقرة|Clause|Article|Section)\s*(\d+(?:\.\d+)*)', user_query)
        if clause_match:
            clause_num = clause_match.group(1)
            print(f"[RAG] Routing to Exact Clause Lookup: {clause_num}")
            exact_results = self.vector_store.search(f"Clause {clause_num}", limit=1)
            if exact_results and exact_results[0]['metadata'].get('clause') == clause_num:
                return {
                    "type": "exact_clause",
                    "answer": exact_results[0]['content'],
                    "source": exact_results[0]['metadata']['filename'],
                    "clause": clause_num
                }

        # 2. Check for structured tabular patterns
        structured_keywords = ["موظف", "عمر", "راتب", "تاريخ الميلاد", "employee", "age", "salary", "born"]
        query_lower = user_query.lower()
        if any(k in query_lower for k in structured_keywords) and re.search(r'\d+', user_query):
            print("[RAG] Routing to Structured Query (simulated)")
            age_range = re.findall(r'\d+', user_query)
            if len(age_range) >= 2:
                v1, v2 = sorted([int(x) for x in age_range[:2]])
                tables = self.structured_store.get_table_info()
                for t in tables:
                    if "age" in t['columns'] or "عمر" in t['columns']:
                        col = "age" if "age" in t['columns'] else "عمر"
                        sql = f"SELECT * FROM {t['table_name']} WHERE {col} BETWEEN {v1} AND {v2}"
                        rows = self.structured_store.query(sql)
                        if rows:
                            answer = f"Found {len(rows)} matching records:\n" + "\n".join([str(dict(r)) for r in rows[:5]])
                            return {
                                "type": "structured_query",
                                "answer": answer,
                                "source": t['filename'],
                                "sql": sql
                            }

        # 3. Default: Semantic Vector Search (large documents only)
        print(f"[RAG] Routing to Semantic Search (top_k={LARGE_DOC_TOP_K})")
        results = self.vector_store.search(user_query, limit=LARGE_DOC_TOP_K)
        if not results:
            return {
                "type": "none",
                "answer": "لم أجد معلومات متعلقة بسؤالك في المستندات المرفوعة.",
                "source": None
            }

        # Dedupe: keep only the best chunk per filename (most relevant wins)
        seen_files = {}
        for res in results:
            fname = res['metadata'].get('filename', '')
            if fname not in seen_files:
                seen_files[fname] = res
        deduped = list(seen_files.values())

        combined_answer = "بناءً على المستندات المرفوعة:\n\n"
        sources = []
        for res in deduped:
            combined_answer += f"- [{res['metadata'].get('filename', '')}]:\n{res['content']}\n"
            sources.append(res['metadata'].get('filename', ''))

        return {
            "type": "semantic_search",
            "answer": combined_answer,
            "sources": sources
        }

    def _get_small_doc_contents(self) -> Dict[str, str]:
        """Retrieve full text of small (full-injection) documents."""
        small_docs = {}
        try:
            results = self.vector_store.collection.get(
                where={"mode": "full_injection"},
                include=["documents", "metadatas"]
            )
            if results and results.get("documents"):
                for doc, meta in zip(results["documents"], results["metadatas"]):
                    fname = meta.get("filename", "") if isinstance(meta, dict) else ""
                    if fname:
                        small_docs[fname] = doc
        except Exception:
            pass
        return small_docs

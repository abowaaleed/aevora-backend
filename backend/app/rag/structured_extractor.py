"""
Structured data extractor for unstructured Arabic documents.

Parses tabular/list patterns (drawer inventories, employee age lists, etc.)
into structured records that can be queried programmatically.
"""

import re
import json
from pathlib import Path
from typing import List, Dict, Any, Optional

DATA_DIR = Path(__file__).parent.parent.parent / "data"
RECORDS_FILE = DATA_DIR / "structured_records.json"


class StructuredRecordStore:
    """Persistent JSON store for structured records extracted from documents."""

    def __init__(self, uid: Optional[str] = None):
        if uid:
            DATA_DIR = Path(__file__).parent.parent.parent / "data" / "users" / uid
        else:
            DATA_DIR = Path(__file__).parent.parent.parent / "data"
        self._records_file = DATA_DIR / "structured_records.json"
        self._records: Dict[str, List[Dict[str, Any]]] = {}  # filename -> records
        self._load()

    def _load(self):
        if self._records_file.exists():
            try:
                with open(self._records_file, "r", encoding="utf-8") as f:
                    self._records = json.load(f)
            except Exception:
                self._records = {}

    def _save(self):
        self._records_file.parent.mkdir(parents=True, exist_ok=True)
        with open(self._records_file, "w", encoding="utf-8") as f:
            json.dump(self._records, f, ensure_ascii=False, indent=2)

    def store(self, filename: str, records: List[Dict[str, Any]]):
        """Store extracted records for a document."""
        if records:
            self._records[filename] = records
            self._save()
            print(f"[STRUCTURED EXTRACT] Stored {len(records)} records for {filename}")

    def get_records(self, filename: str) -> List[Dict[str, Any]]:
        return self._records.get(filename, [])

    def get_all_records(self) -> Dict[str, List[Dict[str, Any]]]:
        return dict(self._records)

    def get_files_with_records(self) -> List[str]:
        return [f for f, r in self._records.items() if r]

    def delete(self, filename: str):
        self._records.pop(filename, None)
        self._save()

    def query_records(
        self,
        filename: Optional[str] = None,
        location: Optional[str] = None,
        item_keyword: Optional[str] = None,
        age_range: Optional[tuple] = None,
        record_type: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """
        Query structured records with optional filters.
        Returns matching records.
        """
        results = []
        sources = self._records if not filename else {filename: self._records.get(filename, [])}

        for fname, records in sources.items():
            for rec in records:
                if record_type and rec.get("type") != record_type:
                    continue
                if location and not _location_matches(rec.get("location", ""), location):
                    continue
                if item_keyword and not _item_matches(rec, item_keyword):
                    continue
                if age_range:
                    age = rec.get("age")
                    if age is None or not (age_range[0] <= age <= age_range[1]):
                        continue
                results.append({**rec, "source_file": fname})

        return results

    def count_records(
        self,
        filename: Optional[str] = None,
        record_type: Optional[str] = None,
        age_range: Optional[tuple] = None,
    ) -> int:
        """Count records matching optional filters."""
        return len(self.query_records(filename=filename, record_type=record_type, age_range=age_range))


def _location_matches(record_location: str, query_location: str) -> bool:
    """Fuzzy match a location string from a record against a query location."""
    rec = record_location.strip().lower()
    q = query_location.strip().lower()
    if q in rec or rec in q:
        return True
    # Extract numbers for numeric comparison
    rec_nums = set(re.findall(r'\d+', rec))
    q_nums = set(re.findall(r'\d+', q))
    if q_nums and q_nums.issubset(rec_nums):
        return True
    return False


def _item_matches(record: Dict[str, Any], keyword: str) -> bool:
    """Check if a record's item or name contains a keyword."""
    keyword = keyword.strip().lower()
    for field in ("item", "name", "description", "type"):
        val = record.get(field, "")
        if isinstance(val, str) and keyword in val.lower():
            return True
    return False


# ── Extraction patterns ──────────────────────────────────────────────────────

# Pattern: "N. Name - عمر X سنة"  (numbered employee list with age)
_EMP_AGE_RE = re.compile(
    r'(?:\d+[\.\)]\s*)?'              # optional leading number + dot/paren
    r'(.+?)\s*-\s*عمر\s+(\d+)\s*سنة',  # Name - عمر N سنة
    re.UNICODE
)

# Pattern: "الدرج رقم N : يوجد فيه X من نوع Y عدد Z" (with "نوع")
_DRAWER_TYPED_RE = re.compile(
    r'الدرج\s+رقم\s+([\d٠-٩]+)\s*[:\s]\s*'  # الدرج رقم N :
    r'(?:يوجد\s+فيه\s+)?'                       # يوجد فيه (optional)
    r'(.+?)\s+نوع\s+(.+?)\s+عدد\s+([\d٠-٩]+)',  # X نوع Y عدد Z
    re.UNICODE
)

# Pattern: "الدرج رقم N : يوجد فيه X عدد Z" (without "نوع")
_DRAWER_BARE_RE = re.compile(
    r'الدرج\s+رقم\s+([\d٠-٩]+)\s*[:\s]\s*'
    r'(?:يوجد\s+فيه\s+)?'
    r'(.+?)\s+عدد\s+([\d٠-٩]+)',
    re.UNICODE
)

# Pattern: "غرفة X يوجد فيها Y نوع Z عدد W" (with "نوع")
_ROOM_TYPED_RE = re.compile(
    r'غرفة\s+(.+?)\s+'                    # غرفة X
    r'(?:يوجد\s+فيها?\s+)?'               # يوجد فيها (optional)
    r'(.+?)\s+نوع\s+(.+?)\s+عدد\s+([\d٠-٩]+)',  # Y نوع Z عدد W
    re.UNICODE
)

# Pattern: "غرفة X يوجد فيها Y عدد W" (without "نوع")
_ROOM_BARE_RE = re.compile(
    r'غرفة\s+(.+?)\s+'
    r'(?:يوجد\s+فيها?\s+)?'
    r'(.+?)\s+عدد\s+([\d٠-٩]+)',
    re.UNICODE
)

# Pattern: simpler "X عدد Y" (item + 数量)
_SIMPLE_COUNT_RE = re.compile(
    r'(.+?)\s+عدد\s+([\d٠-٩]+)',
    re.UNICODE
)

# Pattern: "N موظفين أعمارهم X سنه" (employee count by age group — exact age)
_EMP_COUNT_AGE_RE = re.compile(
    r'([\d٠-٩]+)\s+موظف(?:ين|ف)\s+[أا]عمارهم\s+([\d٠-٩]+)\s+سنه',
    re.UNICODE
)

# Pattern: "N موظف اعمارهم بين X سنه - Y سنه" (employee count by age range)
_EMP_COUNT_AGE_RANGE_RE = re.compile(
    r'([\d٠-٩]+)\s+موظف\s+[أا]عمارهم\s+بين\s+([\d٠-٩]+)\s+سنه\s*[-–]\s*([\d٠-٩]+)\s+سنه',
    re.UNICODE
)

# Pattern: "يحق لصاحب محل صيديليه مساحة المحل من X حتى Y ان يحصل على عدد Z عامل"
# (veterinary clinic range: area → worker count)
_VET_CLINIC_RANGE_RE = re.compile(
    r'يحق\s+لصاحب\s+محل\s+صيد[يى]لي\s*ه?\s+مساحة\s+المحل\s+من\s+([\d٠-٩]+)\s+م\s+'
    r'(?:حتى|إلى|الى)\s+([\d٠-٩]+)\s+م\s+'
    r'ان\s+يحصل\s+على\s+عدد\s+([\d٠-٩]+)\s+عامل',
    re.UNICODE
)

# Pattern: "في X يوجد Y ملف/ملفات" (file count by location)
# Handles: digit counts, "ملفين" (dual=2), "ملف واحد" (word number=1)
# Also handles "يوجد"/"يحتوي"/"يوجد"/"يوحد" verb variations
_FILE_COUNT_RE = re.compile(
    r'في\s+(.+?)\s+(?:يوجد|يحتوي|يوحد)\s+(?:لديه\s+)?(?:([\d٠-٩]+)\s+ملف|ملفين|ملف\s+واحد)',
    re.UNICODE
)

# Pattern: "في بيت X يوجد Y ملف/ملفات كالتالي :" (total file count)
_TOTAL_FILE_COUNT_RE = re.compile(
    r'في\s+(.+?)\s+يوجد\s+([\d٠-٩]+)\s+ملف',
    re.UNICODE
)


def _arabic_to_int(s: str) -> Optional[int]:
    """Convert Arabic-Indic and Western digits to int."""
    s = s.strip()
    arabic_digits = '٠١٢٣٤٥٦٧٨٩'
    translated = ''
    for ch in s:
        idx = arabic_digits.find(ch)
        if idx >= 0:
            translated += str(idx)
        else:
            translated += ch
    try:
        return int(translated)
    except ValueError:
        return None


def _normalize_num(s: str) -> str:
    """Normalize Arabic-Indic digits in a string to Western digits."""
    arabic_digits = '٠١٢٣٤٥٦٧٨٩'
    result = ''
    for ch in s:
        idx = arabic_digits.find(ch)
        if idx >= 0:
            result += str(idx)
        else:
            result += ch
    return result


def extract_records(text: str, filename: str) -> List[Dict[str, Any]]:
    """
    Extract structured records from document text.
    Returns a list of dicts, each with at minimum:
      - type: "employee_age" | "inventory_item"
      - source_file: filename
    Plus type-specific fields.
    """
    records = []

    # 1. Employee age list: "Name - عمر X سنة"
    for m in _EMP_AGE_RE.finditer(text):
        name = m.group(1).strip()
        age = _arabic_to_int(m.group(2))
        if name and age is not None:
            records.append({
                "type": "employee_age",
                "name": name,
                "age": age,
                "source_file": filename,
            })

    # 2. Drawer inventory (with "نوع")
    for m in _DRAWER_TYPED_RE.finditer(text):
        drawer_num = m.group(1).strip()
        description = m.group(2).strip()
        item_type = m.group(3).strip()
        quantity = _arabic_to_int(m.group(4))
        if quantity is not None:
            records.append({
                "type": "inventory_item",
                "location": f"الدرج {_normalize_num(drawer_num)}",
                "item": f"{description} {item_type}",
                "item_type": item_type,
                "quantity": quantity,
                "source_file": filename,
            })

    # 2b. Drawer inventory (without "نوع") — captures drawers 3-6 etc.
    captured_drawer_nums = {re.search(r'\d', m.group(1)).group() for m in _DRAWER_TYPED_RE.finditer(text)}
    for m in _DRAWER_BARE_RE.finditer(text):
        drawer_num = m.group(1).strip()
        norm_num = re.search(r'\d', drawer_num)
        if norm_num and norm_num.group() in captured_drawer_nums:
            continue  # already captured by typed pattern
        description = m.group(2).strip()
        quantity = _arabic_to_int(m.group(3))
        if quantity is not None:
            records.append({
                "type": "inventory_item",
                "location": f"الدرج {_normalize_num(drawer_num)}",
                "item": description,
                "item_type": description.split()[0] if description.split() else description,
                "quantity": quantity,
                "source_file": filename,
            })

    # 3. Room inventory (with "نوع")
    for m in _ROOM_TYPED_RE.finditer(text):
        room = m.group(1).strip()
        description = m.group(2).strip()
        item_type = m.group(3).strip()
        quantity = _arabic_to_int(m.group(4))
        if quantity is not None:
            records.append({
                "type": "inventory_item",
                "location": f"غرفة {room}",
                "item": f"{description} {item_type}",
                "item_type": item_type,
                "quantity": quantity,
                "source_file": filename,
            })

    # 3b. Room inventory (without "نوع")
    captured_rooms = {m.group(1).strip() for m in _ROOM_TYPED_RE.finditer(text)}
    for m in _ROOM_BARE_RE.finditer(text):
        room = m.group(1).strip()
        if room in captured_rooms:
            continue
        description = m.group(2).strip()
        quantity = _arabic_to_int(m.group(3))
        if quantity is not None:
            records.append({
                "type": "inventory_item",
                "location": f"غرفة {room}",
                "item": description,
                "item_type": description.split()[0] if description.split() else description,
                "quantity": quantity,
                "source_file": filename,
            })

    # 4. Simple count pattern: "X عدد Y" (fallback, only if not already captured)
    if not records:
        for m in _SIMPLE_COUNT_RE.finditer(text):
            desc = m.group(1).strip()
            quantity = _arabic_to_int(m.group(2))
            if quantity is not None and quantity > 0:
                records.append({
                    "type": "inventory_item",
                    "location": "",
                    "item": desc,
                    "item_type": desc,
                    "quantity": quantity,
                    "source_file": filename,
                })

    # 5. Employee count by age group: "N موظفين أعمارهم X سنه"
    for m in _EMP_COUNT_AGE_RE.finditer(text):
        count = _arabic_to_int(m.group(1))
        age = _arabic_to_int(m.group(2))
        if count is not None and age is not None:
            records.append({
                "type": "employee_count",
                "count": count,
                "age": age,
                "source_file": filename,
            })

    # 5b. Employee count by age range: "N موظف اعمارهم بين X سنه - Y سنه"
    for m in _EMP_COUNT_AGE_RANGE_RE.finditer(text):
        count = _arabic_to_int(m.group(1))
        age_min = _arabic_to_int(m.group(2))
        age_max = _arabic_to_int(m.group(3))
        if count is not None and age_min is not None and age_max is not None:
            records.append({
                "type": "employee_count_range",
                "count": count,
                "age_min": age_min,
                "age_max": age_max,
                "source_file": filename,
            })

    # 5c. Veterinary clinic range: "يحق لصاحب محل... مساحة... من X حتى Y... عدد Z"
    for m in _VET_CLINIC_RANGE_RE.finditer(text):
        area_min = _arabic_to_int(m.group(1))
        area_max = _arabic_to_int(m.group(2))
        workers = _arabic_to_int(m.group(3))
        if area_min is not None and area_max is not None and workers is not None:
            records.append({
                "type": "range_lookup",
                "category": "عامل محل صيدلية بيطرية",
                "min_value": area_min,
                "max_value": area_max,
                "result_value": workers,
                "result_unit": "عامل",
                "unit_raw": "محل صيدلية",
                "source_text": m.group(0),
                "source_file": filename,
                "ambiguous": False,
            })

    # 6. File count by location: "في X يوجد Y ملف"
    # Handles: digit counts, "ملفين" (dual=2), "ملف واحد" (word number=1)
    def _file_count_from_match(m):
        """Extract count from a _FILE_COUNT_RE match."""
        digit_group = m.group(2)  # digit count group (None for "ملفين"/"ملف واحد")
        if digit_group:
            return _arabic_to_int(digit_group)
        matched = m.group(0)
        if 'ملفين' in matched:
            return 2
        if 'واحد' in matched:
            return 1
        return None

    # First pass: identify parent locations (lines with "كالتالي")
    parent_locations = []
    for m in _FILE_COUNT_RE.finditer(text):
        location = m.group(1).strip()
        is_total = 'كالتالي' in text[m.start():m.end()+20]
        if is_total:
            parent_locations.append(location)

    current_parent = None
    for m in _FILE_COUNT_RE.finditer(text):
        location = m.group(1).strip()
        count = _file_count_from_match(m)
        if count is not None:
            is_total = 'كالتالي' in text[m.start():m.end()+20]
            if is_total:
                current_parent = location
            # For detail records, prefix with parent location
            if current_parent and not is_total:
                display_location = f"{current_parent} - {location}"
            else:
                display_location = location
            records.append({
                "type": "file_count",
                "location": display_location,
                "count": count,
                "is_total": is_total,
                "source_file": filename,
            })

    # 7. Range-lookup records (quota tables with min-max ranges)
    range_records = extract_range_records(text, filename)
    records.extend(range_records)

    return records


# ── Range-lookup extraction ─────────────────────────────────────────────────
#
# Detects Arabic quota/range patterns like:
#   "عدد 100 نخله يحق له الحصول على عدد 1 عامل زراعي"
#   "عدد 200 نخله الى 400 نخله يحق له الحصول على عدد 2 عامل زراعي"
#   "عدد 10 رؤوس اغنام يحق لصاحب الحلال ان يحصل على عدد 1 عامل راعي"
#
# Parses into structured range records and supports deterministic interval matching.

# Category header patterns — these signal a new range-table section
_CATEGORY_HEADER_RE = re.compile(
    r'(?:'
    r'اولا\s*:?\s*(.+?)(?:\s*:|$)'          # "اولا : العامل الزراعي ..."
    r'|ثانيا\s*:?\s*(.+?)(?:\s*:|$)'        # "ثانيا العامل الراعي ..."
    r'|ثالثا\s*:?\s*(.+?)(?:\s*:|$)'        # "ثالثا ..."
    r'|رابعا\s*:?\s*(.+?)(?:\s*:|$)'        # "رابعا ..."
    r'|(?:عامل\s+محل\s+صيدلية\s+بيطرية)'   # "عامل محل صيدلية بيطرية" (no colon)
    r')',
    re.UNICODE | re.IGNORECASE
)

# Known category keyword mappings → canonical category name
_CATEGORY_KEYWORDS = {
    'الزراعي': 'العامل الزراعي',
    'نخل': 'العامل الزراعي',
    'نخله': 'العامل الزراعي',
    'نخلة': 'العامل الزراعي',
    'الراعي': 'العامل الراعي',
    'اغنام': 'العامل الراعي',
    'اغنم': 'العامل الراعي',
    'رأس': 'العامل الراعي',
    'رؤوس': 'العامل الراعي',
    'غنم': 'العامل الراعي',
    'حلال': 'العامل الراعي',
    'صيدلية': 'عامل محل صيدلية بيطرية',
    'صيدليه': 'عامل محل صيدلية بيطرية',
    'بيطرية': 'عامل محل صيدلية بيطرية',
    'بيطريه': 'عامل محل صيدلية بيطرية',
    'محل': 'عامل محل صيدلية بيطرية',
    'مساحة': 'عامل محل صيدلية بيطرية',
}

# Unit keyword mappings — what unit the query number refers to
_UNIT_KEYWORDS = {
    'نخل': 'nakhla',
    'نخله': 'nakhla',
    'نخلة': 'nakhla',
    'نخيل': 'nakhla',
    'اغنام': 'ghonam',
    'اغنم': 'ghonam',
    'غنم': 'ghonam',
    'رأس': 'ghonam',
    'رؤوس': 'ghonam',
    'حلال': 'ghonam',
    'متر': 'meter',
    'م2': 'meter',
    'متر مربع': 'meter',
    'مساحة': 'meter',
}

# Pattern: "عدد X [unit] [الى/حتى/إلى] Y [unit] ... عدد N [result unit]"
# Two forms: range (min-max) and threshold (single number)
_RANGE_PATTERN = re.compile(
    r'[\d٠-٩]+\s*-\s*'                          # numbered list prefix "1-"
    r'عدد\s+([\d٠-٩]+)\s+'                       # "عدد X "
    r'(.+?)\s+'                                   # unit/context words (e.g. "نخله", "رؤوس اغنام")
    r'(?:الى|إلى|حتى)\s+([\d٠-٩]+)\s+'           # "الى/حتى Y "
    r'.+?'                                        # filler text
    r'عدد\s+([\d٠-٩]+)\s+'                       # "عدد N "
    r'(.+?)$',                                    # result unit (e.g. "عامل زراعي")
    re.UNICODE | re.MULTILINE
)

# Pattern: single threshold — "عدد X [unit] ... عدد N [result]"
_THRESHOLD_PATTERN = re.compile(
    r'[\d٠-٩]+\s*-\s*'                          # numbered list prefix
    r'عدد\s+([\d٠-٩]+)\s+'                       # "عدد X "
    r'(.+?)\s+'                                   # unit/context words
    r'(?:يحق|يحصل).+?'                           # "يحق له" / "يحصل على"
    r'عدد\s+([\d٠-٩]+)\s+'                       # "عدد N "
    r'(.+?)$',                                    # result unit
    re.UNICODE | re.MULTILINE
)

# Simpler threshold pattern without numbered list prefix
_THRESHOLD_PATTERN_NO_NUM = re.compile(
    r'عدد\s+([\d٠-٩]+)\s+'                       # "عدد X "
    r'(.+?)\s+'                                   # unit/context words
    r'(?:يحق|يحصل).+?'                           # "يحق له" / "يحصل على"
    r'عدد\s+([\d٠-٩]+)\s+'                       # "عدد N "
    r'(.+?)$',                                    # result unit
    re.UNICODE | re.MULTILINE
)

# Simpler range pattern without numbered list prefix
_RANGE_PATTERN_NO_NUM = re.compile(
    r'عدد\s+([\d٠-٩]+)\s+'                       # "عدد X "
    r'(.+?)\s+'                                   # unit/context words
    r'(?:الى|إلى|حتى)\s+([\d٠-٩]+)\s+'           # "الى/حتى Y "
    r'.+?'                                        # filler text
    r'عدد\s+([\d٠-٩]+)\s+'                       # "عدد N "
    r'(.+?)$',                                    # result unit
    re.UNICODE | re.MULTILINE
)


def _detect_category(text_before: str) -> str:
    """Detect the category (section) a range belongs to based on preceding text."""
    text_lower = text_before.lower()
    for keyword, category in _CATEGORY_KEYWORDS.items():
        if keyword in text_lower:
            return category
    return 'غير محدد'


def _extract_range_value(match_text: str) -> Optional[int]:
    """Extract a number from Arabic-Indic or Western digits."""
    return _arabic_to_int(match_text.strip())


def _parse_range_line(line: str, category: str, filename: str) -> Optional[Dict[str, Any]]:
    """
    Parse a single line that contains a range or threshold pattern.
    Returns a structured range record or None.
    """
    line = line.strip()
    if not line or len(line) < 10:
        return None

    # Try range pattern first (with numbered list prefix)
    m = _RANGE_PATTERN.search(line)
    if m:
        min_val = _arabic_to_int(m.group(1))
        unit_raw = m.group(2).strip()
        max_val = _arabic_to_int(m.group(3))
        result_val = _arabic_to_int(m.group(4))
        result_unit = m.group(5).strip()
        if min_val is not None and max_val is not None and result_val is not None:
            return {
                "type": "range_lookup",
                "category": category,
                "min_value": min_val,
                "max_value": max_val,
                "result_value": result_val,
                "result_unit": result_unit,
                "unit_raw": unit_raw,
                "source_text": line,
                "source_file": filename,
            }

    # Try range pattern without numbered prefix
    m = _RANGE_PATTERN_NO_NUM.search(line)
    if m:
        min_val = _arabic_to_int(m.group(1))
        unit_raw = m.group(2).strip()
        max_val = _arabic_to_int(m.group(3))
        result_val = _arabic_to_int(m.group(4))
        result_unit = m.group(5).strip()
        if min_val is not None and max_val is not None and result_val is not None:
            return {
                "type": "range_lookup",
                "category": category,
                "min_value": min_val,
                "max_value": max_val,
                "result_value": result_val,
                "result_unit": result_unit,
                "unit_raw": unit_raw,
                "source_text": line,
                "source_file": filename,
            }

    # Try threshold pattern (with numbered list prefix)
    m = _THRESHOLD_PATTERN.search(line)
    if m:
        min_val = _arabic_to_int(m.group(1))
        unit_raw = m.group(2).strip()
        result_val = _arabic_to_int(m.group(3))
        result_unit = m.group(4).strip()
        if min_val is not None and result_val is not None:
            return {
                "type": "range_lookup",
                "category": category,
                "min_value": min_val,
                "max_value": None,  # open-ended: "100+ units"
                "result_value": result_val,
                "result_unit": result_unit,
                "unit_raw": unit_raw,
                "source_text": line,
                "source_file": filename,
            }

    # Try threshold pattern without numbered prefix
    m = _THRESHOLD_PATTERN_NO_NUM.search(line)
    if m:
        min_val = _arabic_to_int(m.group(1))
        unit_raw = m.group(2).strip()
        result_val = _arabic_to_int(m.group(3))
        result_unit = m.group(4).strip()
        if min_val is not None and result_val is not None:
            return {
                "type": "range_lookup",
                "category": category,
                "min_value": min_val,
                "max_value": None,
                "result_value": result_val,
                "result_unit": result_unit,
                "unit_raw": unit_raw,
                "source_text": line,
                "source_file": filename,
            }

    return None


def extract_range_records(text: str, filename: str) -> List[Dict[str, Any]]:
    """
    Extract range/threshold records from document text.
    Groups ranges by category (section heading) to prevent cross-category confusion.
    Returns list of range_lookup records.
    """
    records = []
    lines = text.split('\n')
    current_category = 'غير محدد'

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue

        # Detect category headers: "اولا :", "ثانيا :", "رابعا عامل محل صيدلية بيطرية"
        header_match = _CATEGORY_HEADER_RE.search(stripped)
        if header_match:
            # Extract category name from the header
            for group in header_match.groups():
                if group:
                    clean = group.strip().rstrip(':').strip()
                    if clean:
                        # Map to canonical category
                        for keyword, category in _CATEGORY_KEYWORDS.items():
                            if keyword in clean:
                                current_category = category
                                break
                        else:
                            current_category = clean
                    break
            else:
                # "رابعا عامل محل صيدلية بيطرية" — matched the standalone pattern
                for keyword, category in _CATEGORY_KEYWORDS.items():
                    if keyword in stripped:
                        current_category = category
                        break
            continue

        # Try to parse range/threshold from this line
        record = _parse_range_line(stripped, current_category, filename)
        if record:
            records.append(record)

    # Post-process: validate ranges within each category
    validated = []
    by_category = {}
    for r in records:
        cat = r["category"]
        by_category.setdefault(cat, []).append(r)

    for cat, cat_records in by_category.items():
        # Sort by min_value for proper tier analysis
        cat_records.sort(key=lambda r: r["min_value"])
        
        # Check for TRUE conflicts: overlapping ranges with DIFFERENT results
        # In tiered quota systems:
        #   - Boundary touches (where one range ends and next begins) are OK
        #   - Open-ended ranges (max=None) end just before the next tier starts
        #   - Only flag as conflict when the SAME value maps to DIFFERENT results
        has_conflict = False
        conflict_details = []
        
        for i, r1 in enumerate(cat_records):
            for j, r2 in enumerate(cat_records):
                if i >= j:
                    continue
                min1, max1 = r1["min_value"], r1["max_value"]
                min2, max2 = r2["min_value"], r2["max_value"]
                
                # Determine effective ranges accounting for tiered semantics
                # An open-ended range [X, None] means "X or more" but in a tiered
                # system, it actually means "X up to just before the next tier"
                if max1 is None:
                    # This range is open-ended — it ends just before min2 if min2 > min1
                    effective_max1 = (min2 - 1) if min2 > min1 else float('inf')
                else:
                    effective_max1 = max1
                    
                if max2 is None:
                    effective_max2 = (min1 - 1) if min1 > min2 else float('inf')
                else:
                    effective_max2 = max2
                
                # Check for actual overlap (not just boundary touch)
                overlap_lo = max(min1, min2)
                overlap_hi = min(effective_max1, effective_max2)
                has_real_overlap = overlap_lo < overlap_hi
                
                if has_real_overlap:
                    if r1["result_value"] != r2["result_value"]:
                        has_conflict = True
                        r1_range = f"[{min1}-{max1 if max1 else '∞'}]"
                        r2_range = f"[{min2}-{max2 if max2 else '∞'}]"
                        conflict_details.append(
                            f"{r1_range}→{r1['result_value']} "
                            f"يتداخل مع {r2_range}→{r2['result_value']}"
                        )
                        print(f"[RANGE] TRUE CONFLICT in '{cat}': "
                              f"{r1_range}→{r1['result_value']} vs "
                              f"{r2_range}→{r2['result_value']}")
                    else:
                        print(f"[RANGE] Compatible overlap in '{cat}' (OK): "
                              f"[{min1}-{max1}] vs [{min2}-{max2}] (same result)")
                else:
                    print(f"[RANGE] No overlap / boundary touch in '{cat}' (OK): "
                          f"[{min1}-{max1}] vs [{min2}-{max2}]")

        if has_conflict:
            for r in cat_records:
                r["ambiguous"] = True
                r["ambiguity_reason"] = (
                    f"المستند يحتوي على نطاقات متداخلة أو غير واضحة للتصنيف '{cat}': "
                    + "; ".join(conflict_details)
                )
        else:
            for r in cat_records:
                r["ambiguous"] = False

        validated.extend(cat_records)

    return validated


def lookup_range(
    records: List[Dict[str, Any]],
    query_value: int,
    query_unit_hint: Optional[str] = None,
    query_category_hint: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    """
    Deterministic interval matching with tiered-system semantics:
    - Open-ended ranges [X, None] end just before the next tier starts
    - Boundary values belong to the higher tier
    - Returns the single best matching range

    Returns:
      - {"result": ..., "source_text": ..., "category": ..., "ambiguous": False} on match
      - {"ambiguous": True, "reason": ...} if the source ranges conflict
      - None if no matching range found
    """
    # Filter to range_lookup records only
    range_records = [r for r in records if r.get("type") == "range_lookup"]
    if not range_records:
        return None

    # Match by category hint if provided
    if query_category_hint:
        category_matches = [
            r for r in range_records
            if query_category_hint in r.get("category", "")
        ]
        if category_matches:
            range_records = category_matches

    # Match by unit hint if provided
    if query_unit_hint:
        unit_matches = [
            r for r in range_records
            if query_unit_hint in r.get("unit_raw", "")
               or query_unit_hint in r.get("category", "")
        ]
        if unit_matches:
            range_records = unit_matches

    if not range_records:
        return None

    # Sort by min_value for tier-aware matching
    sorted_records = sorted(range_records, key=lambda r: r["min_value"])

    # Find matching range with tiered semantics
    matching = []
    for r in sorted_records:
        min_val = r["min_value"]
        max_val = r["max_value"]
        if max_val is not None:
            # Bounded range: simple interval check
            if min_val <= query_value <= max_val:
                matching.append(r)
        else:
            # Open-ended range: find the next tier that starts at the same or higher value
            next_min = float('inf')
            for other in sorted_records:
                if other is r:
                    continue
                if other["min_value"] >= min_val:
                    next_min = min(next_min, other["min_value"])
            
            if next_min == min_val:
                # A bounded range starts at the same value — this open-ended range
                # is superseded. Skip it entirely (it's redundant/ambiguous).
                continue
            elif next_min == float('inf'):
                # No other range at or above this value — truly open-ended
                effective_max = float('inf')
            else:
                # Next tier starts higher — this range covers [min_val, next_min - 1]
                effective_max = next_min - 1
            
            if min_val <= query_value <= effective_max:
                matching.append(r)

    if not matching:
        return None

    # Check for ambiguity: multiple ranges matching the same value
    if len(matching) > 1:
        results = set(m["result_value"] for m in matching)
        if len(results) == 1:
            r = matching[0]
            return {
                "result": r["result_value"],
                "result_unit": r["result_unit"],
                "source_text": r["source_text"],
                "category": r["category"],
                "ambiguous": False,
            }
        else:
            return {
                "ambiguous": True,
                "reason": (
                    "المستند يحتوي على نطاقات متداخلة أو غير واضحة لهذا التصنيف، "
                    "يرجى مراجعة المستند الأصلي أو توضيح الحدود بدقة."
                ),
                "conflicting_results": [
                    {"min": m["min_value"], "max": m["max_value"], "result": m["result_value"]}
                    for m in matching
                ],
            }

    # Single match — check if this specific range is marked ambiguous
    r = matching[0]
    if r.get("ambiguous"):
        return {
            "ambiguous": True,
            "reason": r.get("ambiguity_reason", "النطاقات متداخلة في هذا التصنيف"),
        }

    return {
        "result": r["result_value"],
        "result_unit": r["result_unit"],
        "source_text": r["source_text"],
        "category": r["category"],
        "ambiguous": False,
    }


def detect_range_query(query: str) -> Optional[Dict[str, Any]]:
    """
    Detect if a user query is asking for a range-based lookup.
    Returns {"value": int, "unit_hint": str, "category_hint": str} or None.

    Examples:
      "عندي 15 رأس غنم كم عامل يحق لي" → {value: 15, unit_hint: "غنم", category_hint: "الراعي"}
      "صاحب مزرعة فيها 300 نخلة كم عامل" → {value: 300, unit_hint: "نخلة", category_hint: "الزراعي"}
      "عندي 5 رؤوس اغنام" → {value: 5, unit_hint: "اغنام", category_hint: "الراعي"}
    """
    # Extract the number from the query
    # Look for patterns like "15 رأس", "300 نخلة", "5 رؤوس"
    number_match = re.search(
        r'(\d+)\s*(?:رأس|رؤوس|نخل[ةه]|نخيل|غنم|اغن[ام]|متر|م2|حلال)',
        query
    )
    if not number_match:
        # Try Arabic-Indic digits
        number_match = re.search(
            r'([\d٠-٩]+)\s*(?:رأس|رؤوس|نخل[ةه]|نخيل|غنم|اغن[ام]|متر|م2|حلال)',
            query
        )
    if not number_match:
        return None

    value = _arabic_to_int(number_match.group(1))
    if value is None:
        return None

    # Detect unit hint from the matched text
    matched_text = number_match.group(0)
    unit_hint = None
    for keyword, unit in _UNIT_KEYWORDS.items():
        if keyword in matched_text:
            unit_hint = unit
            break

    # Detect category hint from the full query
    category_hint = None
    query_lower = query.lower()
    for keyword, category in _CATEGORY_KEYWORDS.items():
        if keyword in query_lower:
            category_hint = category
            break

    # Also check for "صاحب مزرعة" / "صاحب حلال" patterns → category inference
    if not category_hint:
        if 'مزرع' in query or 'نخل' in query:
            category_hint = 'العامل الزراعي'
        elif 'غنم' in query or 'اغنام' in query or 'رأس' in query or 'حلال' in query:
            category_hint = 'العامل الراعي'
        elif 'صيدل' in query or 'بيطر' in query:
            category_hint = 'عامل محل صيدلية بيطرية'

    return {
        "value": value,
        "unit_hint": unit_hint,
        "category_hint": category_hint,
    }


# ── Query answer computation ─────────────────────────────────────────────────

def compute_answer(
    records: List[Dict[str, Any]],
    user_query: str,
) -> Optional[str]:
    """
    Attempt to answer a numeric query using structured records.
    Returns a formatted answer string, or None if the records can't answer it.
    """
    query_lower = user_query.lower()

    # --- 0. Range-lookup (deterministic interval matching) ---
    #     Must run FIRST — it's the most specific and reliable path.
    range_query = detect_range_query(user_query)
    if range_query:
        result = lookup_range(
            records,
            query_value=range_query["value"],
            query_unit_hint=range_query.get("unit_hint"),
            query_category_hint=range_query.get("category_hint"),
        )
        if result:
            if result.get("ambiguous"):
                return result["reason"]
            value = range_query["value"]
            res_val = result["result"]
            res_unit = result.get("result_unit", "")
            category = result.get("category", "")
            source = result.get("source_text", "")
            return (
                f"بناءً على النطاق الوارد في المستند ({source}):\n"
                f"لديك {value} — يحق لك {res_val} {res_unit}.\n"
                f"[التصنيف: {category}]"
            )

    # --- Age-range filter (check BEFORE total count) ---
    # Match "بين X وY" / "من X الى Y" / "X سنه - Y سنه" (supports Arabic-Indic digits)
    _D = r'[\d٠-٩]+'
    age_range_match = re.search(r'بين\s+(' + _D + r')\s+و\s*(' + _D + r')', user_query)
    if not age_range_match:
        age_range_match = re.search(r'من\s+(' + _D + r')\s+إلى\s+(' + _D + r')', user_query)
    if not age_range_match:
        age_range_match = re.search(r'من\s+(' + _D + r')\s+الى\s+(' + _D + r')', user_query)
    if not age_range_match:
        age_range_match = re.search(r'من\s+(' + _D + r')\s+\u0627\u0644\u0649\s+(' + _D + r')', user_query)
    if not age_range_match:
        age_range_match = re.search(r'(' + _D + r')\s+سنه\s*[-–]\s*(' + _D + r')\s+سنه', user_query)

    has_age_context = 'عمر' in user_query or 'أعمار' in user_query or 'اعمار' in user_query

    if has_age_context and age_range_match:
        lo = _arabic_to_int(age_range_match.group(1))
        hi = _arabic_to_int(age_range_match.group(2))
        # Try employee_count_range records first (range format: "200 موظف اعمارهم بين 30-40")
        # Prefer exact match (age_min==lo AND age_max==hi), fall back to overlapping
        all_range_records = [
            r for r in records
            if r.get("type") == "employee_count_range"
        ]
        exact_ranges = [
            r for r in all_range_records
            if r.get("age_min") == lo and r.get("age_max") == hi
        ]
        if exact_ranges:
            range_count_records = exact_ranges
        else:
            range_count_records = [
                r for r in all_range_records
                if r.get("age_min", 0) <= hi and r.get("age_max", 0) >= lo
            ]
        if range_count_records:
            total = sum(r.get("count", 0) for r in range_count_records)
            details = []
            for r in range_count_records:
                details.append(f"{r['count']} موظف بين {r['age_min']} و {r['age_max']} سنة")
            source_files = list(set(r.get("source_file", "") for r in range_count_records))
            return f"العدد: {total} موظف ({'; '.join(details)}).\n[المصدر: {', '.join(source_files)}]"
        # Try employee_count records (summary format)
        count_records = [r for r in records if r.get("type") == "employee_count" and lo <= r.get("age", 0) <= hi]
        if count_records:
            ages = {}
            for r in count_records:
                a = r["age"]
                ages[a] = ages.get(a, 0) + r.get("count", 1)
            detail = " + ".join(f"{count} بعمر {age}" for age, count in sorted(ages.items()))
            total = sum(count_records[i].get("count", 1) for i in range(len(count_records)))
            source_files = list(set(r.get("source_file", "") for r in count_records))
            return f"العدد: {total} موظف ({detail}).\n[المصدر: {', '.join(source_files)}]"
        # Fallback to individual employee_age records
        age_records = [r for r in records if r.get("type") == "employee_age" and lo <= r.get("age", 0) <= hi]
        if age_records:
            ages = {}
            for r in age_records:
                a = r["age"]
                ages[a] = ages.get(a, 0) + 1
            detail = " + ".join(f"{count} بعمر {age}" for age, count in sorted(ages.items()))
            total = len(age_records)
            source_files = list(set(r.get("source_file", "") for r in age_records))
            return f"العدد: {total} موظف ({detail}).\n[المصدر: {', '.join(source_files)}]"

    # --- Exact age query ---
    # Match both digit ("30 سنة") and Arabic word ("ثلاثون سنة") forms
    exact_age_match = re.search(r'عمره?\s*(\d+)\s+سنة', user_query)
    if not exact_age_match:
        # Try Arabic number words
        ARABIC_NUMS = {
            'عشرة': 10, 'عشرون': 20, 'ثلاثون': 30, 'اربعون': 40, 'أربعون': 40,
            'خمسون': 50, 'ستون': 60, 'سبعون': 70, 'ثمانون': 80, 'تسعون': 90,
            'مائة': 100, 'مئة': 100,
        }
        for word, num in ARABIC_NUMS.items():
            if word in user_query:
                exact_age_match_num = num
                break
        else:
            exact_age_match_num = None
    else:
        exact_age_match_num = int(exact_age_match.group(1))

    if exact_age_match_num is not None:
        age_records = [r for r in records if r.get("type") == "employee_age" and r.get("age") == exact_age_match_num]
        if age_records:
            total = len(age_records)
            source_files = list(set(r.get("source_file", "") for r in age_records))
            return f"عدد الموظفين بعمر {exact_age_match_num} سنة: {total}.\n[المصدر: {', '.join(source_files)}]"

    # --- Reverse range-lookup: user wants output, asks for input ---
    # Pattern: "اذا كنت اريد X عامل/عون" or "اريد X عامل" or "اريد عامل واحد" or "اريد عامل زراعي واحد"
    reverse_worker_match = re.search(r'اريد\s+([\d٠-٩]+)\s+عامل', user_query)
    if not reverse_worker_match:
        reverse_worker_match = re.search(r'اريد\s+عامل\s+(?:زراعي\s+)?واحد', user_query)
        if reverse_worker_match:
            desired_workers = 1
        else:
            desired_workers = None
    else:
        desired_workers = _arabic_to_int(reverse_worker_match.group(1))
    if desired_workers is not None:
        # Find range_lookup records matching this worker count
        matching = [
            r for r in records
            if r.get("type") == "range_lookup"
            and r.get("result_value") == desired_workers
            and not r.get("ambiguous")
        ]
        if matching:
            r = matching[0]
            min_v = r.get("min_value")
            max_v = r.get("max_value")
            category = r.get("category", "")
            unit_raw = r.get("unit_raw", "")
            result_unit = r.get("result_unit", "")
            if min_v is not None and max_v is not None:
                return (
                    f"للحصول على {desired_workers} {result_unit} ({category}):\n"
                    f"تحتاج {unit_raw} بمساحة من {min_v} حتى {max_v} متر مربع.\n"
                    f"[النطاق: {r.get('source_text', '')}]"
                )
            elif min_v is not None and max_v is None:
                # Open-ended range: "100 م فما فوق"
                return (
                    f"للحصول على {desired_workers} {result_unit} ({category}):\n"
                    f"تحتاج {unit_raw} بمساحة {min_v} متر مربع فما فوق.\n"
                    f"[النطاق: {r.get('source_text', '')}]"
                )

    # --- Total count (employees) ---
    total_patterns = [
        r'كم\s+عدد\s+(?:الموظفين|العاملين|الاشخاص|الموظف)',
        r'عدد\s+(?:الموظفين|العاملين)',
        r'اجمالي\s+(?:عدد\s+)?(?:الموظفين|العاملين)',
        r'عدد\s+الموظفين\s+في\s+فرع',  # "عدد الموظفين في فرع وزارة"
    ]
    for pat in total_patterns:
        if re.search(pat, user_query):
            # Try employee_count_range records first (range format)
            range_count_records = [r for r in records if r.get("type") == "employee_count_range"]
            if range_count_records:
                total = sum(r.get("count", 0) for r in range_count_records)
                details = []
                for r in range_count_records:
                    details.append(f"{r['count']} بين {r['age_min']} و {r['age_max']} سنة")
                source_files = list(set(r.get("source_file", "") for r in range_count_records))
                return f"العدد الإجمالي: {total} موظف ({'; '.join(details)}).\n[المصدر: {', '.join(source_files)}]"
            # Try employee_count records (summary format: "10 موظفين أعمارهم 30")
            count_records = [r for r in records if r.get("type") == "employee_count"]
            if count_records:
                total = sum(r.get("count", 0) for r in count_records)
                ages = {r["age"]: r["count"] for r in count_records}
                detail = " + ".join(f"{cnt} بعمر {age}" for age, cnt in sorted(ages.items()))
                source_files = list(set(r.get("source_file", "") for r in count_records))
                return f"العدد الإجمالي: {total} موظف ({detail}).\n[المصدر: {', '.join(source_files)}]"
            # Fallback to individual employee_age records
            age_records = [r for r in records if r.get("type") == "employee_age"]
            total = len(age_records)
            if total > 0:
                source_files = list(set(r.get("source_file", "") for r in age_records))
                return f"العدد الإجمالي: {total} {'سجل' if total != 1 else 'سجل'}.\n[المصدر: {', '.join(source_files)}]"

    # --- File count queries ---
    file_count_patterns = [
        r'كم\s+عدد\s+(?:ال)?(?:ملفات|ملف)',  # "كم عدد الملفات" or "كم عدد ملفات"
        r'عدد\s+(?:ال)?(?:ملفات|ملف)',
        r'كم\s+ملف(?:ات)?(?:\s+هناك)?',
        r'كم\s+عددها',  # "في بيت الشروق يوجد ملفات كم عددها"
        r'كم\s+عدده',   # masculine form
    ]
    for pat in file_count_patterns:
        if re.search(pat, user_query):
            file_records = [r for r in records if r.get("type") == "file_count"]
            if file_records:
                # Check if query specifies a location
                location_keywords = {
                    'الربوه': 'بيت الربوه',
                    'الربوة': 'بيت الربوه',
                    'الشروق': 'بيت الشروق',
                    'الصاله': 'الصاله',
                    'الصالح': 'الصاله',
                    'السطح': 'السطح',
                    'المطبخ': 'المطبخ',
                    'الرئيسيه': 'الغرفة الرئيسيه',
                    'الرئيسي': 'الغرفة الرئيسيه',
                    'الملحق': 'الملحق الخارجي',
                }
                matched_location = None
                for kw, loc in location_keywords.items():
                    if kw in user_query:
                        matched_location = loc
                        break

                if matched_location:
                    # Filter to specific location (match parent or detail)
                    matching = [r for r in file_records if matched_location in r.get("location", "")]
                    if matching:
                        # Use total record if available, else sum details
                        total_rec = [r for r in matching if r.get("is_total")]
                        if total_rec:
                            total = sum(r.get("count", 0) for r in total_rec)
                        else:
                            total = sum(r.get("count", 0) for r in matching)
                        source_files = list(set(r.get("source_file", "") for r in matching))
                        return f"عدد الملفات في {matched_location}: {total}.\n[المصدر: {', '.join(source_files)}]"
                else:
                    # Total across all locations
                    # Use total records (is_total=True) if available, else sum details
                    total_records = [r for r in file_records if r.get("is_total")]
                    if total_records:
                        # Group by source file to get per-location totals
                        location_totals = {}
                        for r in total_records:
                            loc = r.get("location", "")
                            location_totals[loc] = location_totals.get(loc, 0) + r.get("count", 0)
                        total = sum(location_totals.values())
                    else:
                        total = sum(r.get("count", 0) for r in file_records)
                    if total > 0:
                        source_files = list(set(r.get("source_file", "") for r in file_records))
                        return f"العدد الإجمالي للملفات: {total}.\n[المصدر: {', '.join(source_files)}]"

    # --- List files in a location ---
    list_patterns = [
        r'اذكر\s+(?:الملفات|الملف)',
        r'اذكرها',  # suffix pronoun "في بيت الربوة يوجد 10 ملفات اذكرها"
        r'اين\s+(?:هي|هم| bulun)',  # "في بيت الشروق يوجد 3 ملفات اذكر اين هي؟"
        r'ما\s+(?:هي|هو)\s+الملفات',
        r'اين\s+(?:توجد|يوجد|تقع|يقع)',  # "اين توجد الملفات"
        r'列出|list',
    ]
    for pat in list_patterns:
        if re.search(pat, user_query):
            file_records = [r for r in records if r.get("type") == "file_count" and not r.get("is_total")]
            if file_records:
                # Check if query specifies a location
                location_keywords = {
                    'الربوه': 'بيت الربوه',
                    'الربوة': 'بيت الربوه',
                    'الشروق': 'بيت الشروق',
                }
                matched_location = None
                for kw, loc in location_keywords.items():
                    if kw in user_query:
                        matched_location = loc
                        break

                if matched_location:
                    matching = [r for r in file_records if matched_location in r.get("location", "")]
                    if matching:
                        lines = [f"في {r['location']} يوجد {r['count']} ملف" for r in matching]
                        source_files = list(set(r.get("source_file", "") for r in matching))
                        return "\n".join(lines) + f"\n[المصدر: {', '.join(source_files)}]"
                else:
                    # List all
                    lines = [f"في {r['location']} يوجد {r['count']} ملف" for r in file_records]
                    source_files = list(set(r.get("source_file", "") for r in file_records))
                    return "\n".join(lines) + f"\n[المصدر: {', '.join(source_files)}]"

    # --- Inventory lookup by location ---
    location_match = re.search(r'(الدرج|درج|غرفة)\s*(رقم\s*)?(\d+|[^\s]+)', user_query)
    if location_match:
        loc_keyword = location_match.group(1)
        loc_num = _normalize_num(location_match.group(3))
        full_loc = f"{loc_keyword} {loc_num}".strip()
        inv_records = [r for r in records if r.get("type") == "inventory_item"]
        matching = [r for r in inv_records if _location_matches(r.get("location", ""), full_loc)]
        if matching:
            lines = []
            for r in matching:
                lines.append(f"{r['item']}: {r['quantity']}")
            source_files = list(set(r.get("source_file", "") for r in matching))
            return "\n".join(lines) + f"\n[المصدر: {', '.join(source_files)}]"

    # --- Inventory lookup by item keyword ---
    item_keywords = {
        'سماع': 'سماع',
        'لابتوب': 'لابتوب',
        'نظار': 'نظار',
        'رسفر': 'رسفر',
        'اقلام': 'اقلام',
        'قلم': 'اقلام',
        'شاش': 'شاش',
        'منشار': 'منشار',
        'جوت': 'جنوط',
        'تويا': 'تويا',
        'جوال': 'جوال',
        'هاتف': 'هاتف',
        'سوني': 'سوني',
        'ابل': 'ابل',
        'ديل': 'ديل',
        'سامسونق': 'سامسونق',
        'شاومي': 'شاومي',
        'بوش': 'بوش',
    }
    for arabic_kw, search_kw in item_keywords.items():
        if arabic_kw in user_query:
            inv_records = [r for r in records if r.get("type") == "inventory_item"]
            matching = [r for r in inv_records if search_kw in r.get("item", "") or search_kw in r.get("item_type", "")]
            if matching:
                total = sum(r.get("quantity", 0) for r in matching)
                # Build descriptive answer mentioning item name and location
                parts = []
                for r in matching:
                    loc = r.get("location", "")
                    item_name = r.get("item_type", r.get("item", ""))
                    qty = r.get("quantity", 0)
                    if loc:
                        parts.append(f"{qty} في {loc}")
                    else:
                        parts.append(f"{qty}")
                source_files = list(set(r.get("source_file", "") for r in matching))
                detail = " و".join(parts)
                # Use the matched keyword to build a descriptive answer
                return f"عدد {user_query.split('عدد')[-1].strip() if 'عدد' in user_query else arabic_kw}: {total} ({detail}).\n[المصدر: {', '.join(source_files)}]"

    return None

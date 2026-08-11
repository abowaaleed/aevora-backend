import sqlite3
import pandas as pd
import re
from pathlib import Path
from typing import List, Dict, Any, Optional

class StructuredStore:
    """
    Wrapper for local SQLite storage for tabular data.
    """
    def __init__(self, uid: Optional[str] = None):
        if uid:
            self.db_path = Path(__file__).parent.parent.parent / "data" / "users" / uid / "structured_data.db"
        else:
            self.db_path = Path(__file__).parent.parent.parent / "data" / "structured_data.db"
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_metadata_table()

    def _init_metadata_table(self):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("CREATE TABLE IF NOT EXISTS file_metadata (filename TEXT PRIMARY KEY, table_name TEXT, columns TEXT)")

    def _sanitize_name(self, name: str) -> str:
        """Sanitize name for SQLite table/column."""
        return re.sub(r'[^a-zA-Z0-9_]', '_', name).lower()

    def load_file(self, filename: str, df: pd.DataFrame):
        """Load a DataFrame into a new SQLite table."""
        table_name = self._sanitize_name(f"tbl_{filename}")

        # Sanitize column names
        df.columns = [self._sanitize_name(col) for col in df.columns]

        with sqlite3.connect(self.db_path) as conn:
            df.to_sql(table_name, conn, if_exists='replace', index=False)
            columns_str = ",".join(df.columns)
            conn.execute("INSERT OR REPLACE INTO file_metadata VALUES (?, ?, ?)", (filename, table_name, columns_str))

        return table_name

    def query(self, sql: str) -> List[Dict[str, Any]]:
        """Execute a raw SQL query."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute(sql)
                rows = cursor.fetchall()
                return [dict(row) for row in rows]
        except Exception as e:
            print(f"[STRUCTURED STORE] Query error: {e}")
            return []

    def get_table_info(self) -> List[Dict[str, Any]]:
        """Get info about all available tables."""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute("SELECT * FROM file_metadata")
            return [dict(row) for row in cursor.fetchall()]

    def delete_file(self, filename: str):
        """Delete table associated with a file."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute("SELECT table_name FROM file_metadata WHERE filename = ?", (filename,))
            row = cursor.fetchone()
            if row:
                conn.execute(f"DROP TABLE IF EXISTS {row[0]}")
                conn.execute("DELETE FROM file_metadata WHERE filename = ?", (filename,))

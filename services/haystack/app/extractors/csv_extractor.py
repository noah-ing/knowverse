"""
CSV Text Extractor

Extracts text content from CSV files, converting tabular data
into a searchable text format with markdown table representation.
"""

import csv
import io
import logging
from typing import Dict, Any, Union, List
from pathlib import Path

logger = logging.getLogger(__name__)


def extract_text_from_csv(
    source: Union[str, Path, bytes, io.BytesIO],
    max_rows: int = 10000,
    include_stats: bool = True
) -> Dict[str, Any]:
    """
    Extract text content from a CSV file.

    Args:
        source: File path, bytes, or BytesIO object
        max_rows: Maximum rows to process (default 10000)
        include_stats: Include statistical summary for numeric columns

    Returns:
        Dictionary with extraction results
    """
    try:
        # Handle different source types
        if isinstance(source, (str, Path)):
            with open(source, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
        elif isinstance(source, bytes):
            # Try UTF-8 first, then fall back to latin-1
            try:
                content = source.decode('utf-8')
            except UnicodeDecodeError:
                content = source.decode('latin-1')
        elif isinstance(source, io.BytesIO):
            source.seek(0)
            try:
                content = source.read().decode('utf-8')
            except UnicodeDecodeError:
                source.seek(0)
                content = source.read().decode('latin-1')
        else:
            return {
                "success": False,
                "content": "",
                "errors": ["Invalid source type"]
            }

        # Parse CSV
        reader = csv.reader(io.StringIO(content))
        rows = list(reader)

        if not rows:
            return {
                "success": True,
                "content": "[Empty CSV file]",
                "total_rows": 0,
                "total_columns": 0,
                "errors": []
            }

        headers = rows[0] if rows else []
        data_rows = rows[1:max_rows + 1] if len(rows) > 1 else []

        # Build text representation
        text_parts = []

        # Header summary
        text_parts.append(f"CSV Data with {len(headers)} columns and {len(rows) - 1} rows\n")
        text_parts.append(f"Columns: {', '.join(headers)}\n")

        # Markdown table representation (first 100 rows for searchability)
        preview_rows = data_rows[:100]
        if headers and preview_rows:
            text_parts.append("\n## Data Preview\n")
            text_parts.append("| " + " | ".join(str(h) for h in headers) + " |")
            text_parts.append("| " + " | ".join("---" for _ in headers) + " |")
            for row in preview_rows:
                # Pad row if necessary
                padded_row = row + [''] * (len(headers) - len(row)) if len(row) < len(headers) else row[:len(headers)]
                text_parts.append("| " + " | ".join(str(cell)[:50] for cell in padded_row) + " |")

        # Include stats for numeric columns
        if include_stats and data_rows:
            stats = _compute_column_stats(headers, data_rows)
            if stats:
                text_parts.append("\n## Column Statistics\n")
                for col_name, col_stats in stats.items():
                    text_parts.append(f"- **{col_name}**: {col_stats}")

        # Full text dump for search (all values space-separated)
        text_parts.append("\n## Full Content\n")
        all_values = []
        for row in data_rows:
            all_values.extend([str(cell).strip() for cell in row if str(cell).strip()])
        text_parts.append(" ".join(all_values[:5000]))  # Limit for very large CSVs

        full_content = "\n".join(text_parts)

        return {
            "success": True,
            "content": full_content,
            "total_rows": len(rows) - 1,
            "total_columns": len(headers),
            "headers": headers,
            "total_chars": len(full_content),
            "total_words": len(full_content.split()),
            "metadata": {
                "row_count": len(rows) - 1,
                "column_count": len(headers),
                "columns": headers
            },
            "errors": []
        }

    except Exception as e:
        logger.error(f"CSV extraction failed: {e}")
        return {
            "success": False,
            "content": "",
            "errors": [f"CSV extraction failed: {str(e)}"]
        }


def _compute_column_stats(headers: List[str], rows: List[List[str]]) -> Dict[str, str]:
    """Compute basic statistics for numeric columns."""
    stats = {}

    for col_idx, header in enumerate(headers):
        values = []
        for row in rows:
            if col_idx < len(row):
                try:
                    val = float(row[col_idx].replace(',', ''))
                    values.append(val)
                except (ValueError, AttributeError):
                    pass

        if len(values) > 5:  # Only if we have enough numeric values
            min_val = min(values)
            max_val = max(values)
            avg_val = sum(values) / len(values)
            stats[header] = f"min={min_val:.2f}, max={max_val:.2f}, avg={avg_val:.2f}, count={len(values)}"

    return stats

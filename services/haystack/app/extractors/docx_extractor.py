"""
Word Document (DOCX) Text Extractor

Enterprise-grade DOCX text extraction using python-docx with
structure preservation, table extraction, and metadata handling.

Features:
- Paragraph and heading extraction with style preservation
- Table extraction with structure
- List handling (bullets, numbered)
- Document metadata extraction
- Header/footer support
"""

import logging
from pathlib import Path
from typing import Dict, List, Any, Optional, Union
from dataclasses import dataclass, field
import io

logger = logging.getLogger(__name__)


@dataclass
class ExtractedTable:
    """Represents an extracted table from a DOCX document."""
    table_index: int
    headers: List[str]
    rows: List[List[str]]
    row_count: int
    column_count: int

    def to_markdown(self) -> str:
        """Convert table to markdown format."""
        if not self.headers and not self.rows:
            return ""

        lines = []

        # Use headers if available, otherwise use first row
        header_row = self.headers if self.headers else (self.rows[0] if self.rows else [])
        data_rows = self.rows if self.headers else self.rows[1:]

        if header_row:
            lines.append("| " + " | ".join(str(cell) for cell in header_row) + " |")
            lines.append("| " + " | ".join("---" for _ in header_row) + " |")

        for row in data_rows:
            # Pad row if it has fewer cells than header
            padded_row = row + [""] * (len(header_row) - len(row)) if len(row) < len(header_row) else row
            lines.append("| " + " | ".join(str(cell) for cell in padded_row) + " |")

        return "\n".join(lines)


@dataclass
class ExtractedSection:
    """Represents a section/paragraph from a DOCX document."""
    index: int
    text: str
    style: str  # e.g., "Heading 1", "Normal", "List Paragraph"
    level: int = 0  # Heading level (0 for non-headings)
    is_list_item: bool = False
    list_type: Optional[str] = None  # "bullet" or "numbered"


@dataclass
class DOCXExtractionResult:
    """Complete extraction result from a DOCX document."""
    success: bool
    content: str
    sections: List[ExtractedSection] = field(default_factory=list)
    tables: List[ExtractedTable] = field(default_factory=list)
    total_paragraphs: int = 0
    total_tables: int = 0
    total_chars: int = 0
    total_words: int = 0
    metadata: Dict[str, Any] = field(default_factory=dict)
    errors: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "success": self.success,
            "content": self.content,
            "sections": [
                {
                    "index": s.index,
                    "text": s.text,
                    "style": s.style,
                    "level": s.level,
                    "is_list_item": s.is_list_item,
                    "list_type": s.list_type
                }
                for s in self.sections
            ],
            "tables": [
                {
                    "table_index": t.table_index,
                    "headers": t.headers,
                    "rows": t.rows,
                    "row_count": t.row_count,
                    "column_count": t.column_count
                }
                for t in self.tables
            ],
            "total_paragraphs": self.total_paragraphs,
            "total_tables": self.total_tables,
            "total_chars": self.total_chars,
            "total_words": self.total_words,
            "metadata": self.metadata,
            "errors": self.errors
        }


class DOCXExtractor:
    """
    Enterprise DOCX text extractor with structure preservation.

    Extracts text from Word documents while preserving:
    - Document structure (headings, paragraphs)
    - Tables with formatting
    - Lists (bulleted and numbered)
    - Document metadata
    """

    def __init__(self,
                 extract_tables: bool = True,
                 preserve_structure: bool = True,
                 include_headers_footers: bool = False):
        """
        Initialize the DOCX extractor.

        Args:
            extract_tables: Whether to extract tables separately
            preserve_structure: Whether to preserve document structure
            include_headers_footers: Whether to include header/footer content
        """
        self.extract_tables = extract_tables
        self.preserve_structure = preserve_structure
        self.include_headers_footers = include_headers_footers

        # Check if python-docx is available
        self._docx_available = self._check_docx()
        if not self._docx_available:
            raise ImportError(
                "python-docx not available. Install it: pip install python-docx"
            )

    def _check_docx(self) -> bool:
        """Check if python-docx is available."""
        try:
            import docx
            return True
        except ImportError:
            logger.error("python-docx not available")
            return False

    def extract(self, source: Union[str, Path, bytes, io.BytesIO]) -> DOCXExtractionResult:
        """
        Extract text and tables from a DOCX document.

        Args:
            source: File path, bytes, or BytesIO object

        Returns:
            DOCXExtractionResult with extracted content and metadata
        """
        from docx import Document
        from docx.oxml.ns import qn

        errors: List[str] = []
        sections: List[ExtractedSection] = []
        tables: List[ExtractedTable] = []
        metadata: Dict[str, Any] = {}

        try:
            # Handle different source types
            if isinstance(source, (str, Path)):
                file_path = Path(source)
                if not file_path.exists():
                    return DOCXExtractionResult(
                        success=False,
                        content="",
                        errors=[f"File not found: {file_path}"]
                    )
                doc = Document(str(file_path))
            elif isinstance(source, bytes):
                doc = Document(io.BytesIO(source))
            else:
                doc = Document(source)

            # Extract metadata
            metadata = self._extract_metadata(doc)

            # Extract paragraphs and headings
            section_index = 0
            for para in doc.paragraphs:
                text = para.text.strip()
                if not text:
                    continue

                style_name = para.style.name if para.style else "Normal"
                level = self._get_heading_level(style_name)
                is_list, list_type = self._detect_list(para)

                sections.append(ExtractedSection(
                    index=section_index,
                    text=text,
                    style=style_name,
                    level=level,
                    is_list_item=is_list,
                    list_type=list_type
                ))
                section_index += 1

            # Extract tables
            if self.extract_tables:
                for table_idx, table in enumerate(doc.tables):
                    try:
                        extracted_table = self._extract_table(table, table_idx)
                        tables.append(extracted_table)
                    except Exception as e:
                        errors.append(f"Table {table_idx} extraction failed: {str(e)}")

            # Include headers/footers if requested
            if self.include_headers_footers:
                header_footer_text = self._extract_headers_footers(doc)
                if header_footer_text:
                    sections.insert(0, ExtractedSection(
                        index=-1,
                        text=header_footer_text,
                        style="Header/Footer",
                        level=0
                    ))

            # Combine content
            full_content = self._combine_content(sections, tables)

            return DOCXExtractionResult(
                success=True,
                content=full_content,
                sections=sections,
                tables=tables,
                total_paragraphs=len(sections),
                total_tables=len(tables),
                total_chars=len(full_content),
                total_words=len(full_content.split()),
                metadata=metadata,
                errors=errors
            )

        except Exception as e:
            logger.error(f"DOCX extraction failed: {e}")
            return DOCXExtractionResult(
                success=False,
                content="",
                errors=[f"Extraction failed: {str(e)}"]
            )

    def _extract_metadata(self, doc) -> Dict[str, Any]:
        """Extract document metadata."""
        metadata = {}

        try:
            core_props = doc.core_properties
            metadata = {
                "title": core_props.title or "",
                "author": core_props.author or "",
                "subject": core_props.subject or "",
                "keywords": core_props.keywords or "",
                "created": str(core_props.created) if core_props.created else "",
                "modified": str(core_props.modified) if core_props.modified else "",
                "last_modified_by": core_props.last_modified_by or "",
                "revision": core_props.revision,
                "category": core_props.category or "",
                "comments": core_props.comments or "",
            }
        except Exception as e:
            logger.warning(f"Could not extract all metadata: {e}")

        return metadata

    def _get_heading_level(self, style_name: str) -> int:
        """Determine heading level from style name."""
        if not style_name:
            return 0

        style_lower = style_name.lower()

        # Check for heading styles
        if style_lower.startswith("heading"):
            try:
                # Extract number from "Heading 1", "Heading 2", etc.
                level = int(style_lower.replace("heading", "").strip())
                return min(level, 6)  # Cap at 6
            except ValueError:
                return 0

        # Check for title
        if style_lower == "title":
            return 1

        return 0

    def _detect_list(self, para) -> tuple:
        """Detect if paragraph is a list item and its type."""
        from docx.oxml.ns import qn

        try:
            # Check for numbering
            numPr = para._element.find(qn('w:pPr'))
            if numPr is not None:
                numId = numPr.find(qn('w:numPr'))
                if numId is not None:
                    # Has numbering - determine type
                    style_name = para.style.name.lower() if para.style else ""
                    if "bullet" in style_name or "list bullet" in style_name:
                        return True, "bullet"
                    elif "number" in style_name or "list number" in style_name:
                        return True, "numbered"
                    else:
                        return True, "bullet"  # Default to bullet
        except Exception:
            pass

        # Check style name
        if para.style:
            style_name = para.style.name.lower()
            if "list" in style_name:
                if "bullet" in style_name:
                    return True, "bullet"
                elif "number" in style_name:
                    return True, "numbered"
                else:
                    return True, "bullet"

        return False, None

    def _extract_table(self, table, table_idx: int) -> ExtractedTable:
        """Extract a table with its structure."""
        rows = []
        max_cols = 0

        for row in table.rows:
            row_cells = []
            for cell in row.cells:
                # Get cell text, handling merged cells
                cell_text = cell.text.strip()
                row_cells.append(cell_text)
            rows.append(row_cells)
            max_cols = max(max_cols, len(row_cells))

        # Normalize row lengths
        for row in rows:
            while len(row) < max_cols:
                row.append("")

        # First row as headers (common convention)
        headers = rows[0] if rows else []
        data_rows = rows[1:] if len(rows) > 1 else []

        return ExtractedTable(
            table_index=table_idx,
            headers=headers,
            rows=data_rows,
            row_count=len(data_rows),
            column_count=max_cols
        )

    def _extract_headers_footers(self, doc) -> str:
        """Extract header and footer text."""
        texts = []

        try:
            for section in doc.sections:
                # Header
                if section.header:
                    for para in section.header.paragraphs:
                        if para.text.strip():
                            texts.append(f"[Header] {para.text.strip()}")

                # Footer
                if section.footer:
                    for para in section.footer.paragraphs:
                        if para.text.strip():
                            texts.append(f"[Footer] {para.text.strip()}")
        except Exception as e:
            logger.warning(f"Could not extract headers/footers: {e}")

        return "\n".join(texts)

    def _combine_content(self, sections: List[ExtractedSection], tables: List[ExtractedTable]) -> str:
        """Combine sections and tables into unified content."""
        content_parts = []

        for section in sections:
            if section.level > 0:
                # Heading - add markdown heading
                prefix = "#" * section.level
                content_parts.append(f"{prefix} {section.text}")
            elif section.is_list_item:
                # List item
                if section.list_type == "numbered":
                    content_parts.append(f"1. {section.text}")
                else:
                    content_parts.append(f"- {section.text}")
            else:
                # Regular paragraph
                content_parts.append(section.text)

        # Add tables at the end with clear markers
        if tables:
            content_parts.append("\n## Tables\n")
            for table in tables:
                md_table = table.to_markdown()
                if md_table:
                    content_parts.append(f"### Table {table.table_index + 1}")
                    content_parts.append(md_table)

        return "\n\n".join(content_parts)


def extract_text_from_docx(
    source: Union[str, Path, bytes, io.BytesIO],
    extract_tables: bool = True,
    preserve_structure: bool = True
) -> Dict[str, Any]:
    """
    Convenience function to extract text from a DOCX file.

    Args:
        source: File path, bytes, or BytesIO object
        extract_tables: Whether to extract tables
        preserve_structure: Whether to preserve document structure

    Returns:
        Dictionary with extraction results
    """
    extractor = DOCXExtractor(
        extract_tables=extract_tables,
        preserve_structure=preserve_structure
    )
    result = extractor.extract(source)
    return result.to_dict()

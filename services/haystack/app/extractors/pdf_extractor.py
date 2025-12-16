"""
PDF Text Extractor

Enterprise-grade PDF text extraction using pdfplumber for layout-aware
extraction with table detection, falling back to pypdf for simpler documents.

Features:
- Layout-preserving text extraction
- Table detection and structured extraction
- Page-by-page processing with metadata
- Robust error handling with fallback strategies
"""

import logging
from pathlib import Path
from typing import Dict, List, Any, Optional, Union
from dataclasses import dataclass, field, asdict
import io

logger = logging.getLogger(__name__)


@dataclass
class ExtractedTable:
    """Represents an extracted table from a PDF page."""
    page_number: int
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
            lines.append("| " + " | ".join(str(cell) for cell in row) + " |")

        return "\n".join(lines)


@dataclass
class ExtractedPage:
    """Represents extracted content from a single PDF page."""
    page_number: int
    text: str
    tables: List[ExtractedTable] = field(default_factory=list)
    char_count: int = 0
    word_count: int = 0

    def __post_init__(self):
        if self.text:
            self.char_count = len(self.text)
            self.word_count = len(self.text.split())


@dataclass
class PDFExtractionResult:
    """Complete extraction result from a PDF document."""
    success: bool
    content: str
    pages: List[ExtractedPage] = field(default_factory=list)
    total_pages: int = 0
    total_tables: int = 0
    total_chars: int = 0
    total_words: int = 0
    metadata: Dict[str, Any] = field(default_factory=dict)
    errors: List[str] = field(default_factory=list)
    extraction_method: str = "pdfplumber"

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "success": self.success,
            "content": self.content,
            "pages": [
                {
                    "page_number": p.page_number,
                    "text": p.text,
                    "tables": [asdict(t) for t in p.tables],
                    "char_count": p.char_count,
                    "word_count": p.word_count
                }
                for p in self.pages
            ],
            "total_pages": self.total_pages,
            "total_tables": self.total_tables,
            "total_chars": self.total_chars,
            "total_words": self.total_words,
            "metadata": self.metadata,
            "errors": self.errors,
            "extraction_method": self.extraction_method
        }


class PDFExtractor:
    """
    Enterprise PDF text extractor with multiple extraction strategies.

    Primary: pdfplumber (layout-aware, table extraction)
    Fallback: pypdf (faster, simpler extraction)
    """

    def __init__(self,
                 extract_tables: bool = True,
                 preserve_layout: bool = True,
                 table_settings: Optional[Dict[str, Any]] = None):
        """
        Initialize the PDF extractor.

        Args:
            extract_tables: Whether to extract tables separately
            preserve_layout: Whether to preserve text layout
            table_settings: Custom settings for table extraction
        """
        self.extract_tables = extract_tables
        self.preserve_layout = preserve_layout
        self.table_settings = table_settings or {
            "vertical_strategy": "lines",
            "horizontal_strategy": "lines",
            "snap_tolerance": 3,
            "join_tolerance": 3,
        }

        # Check available libraries
        self._pdfplumber_available = self._check_pdfplumber()
        self._pypdf_available = self._check_pypdf()

        if not self._pdfplumber_available and not self._pypdf_available:
            raise ImportError(
                "No PDF extraction library available. "
                "Install pdfplumber or pypdf: pip install pdfplumber pypdf"
            )

    def _check_pdfplumber(self) -> bool:
        """Check if pdfplumber is available."""
        try:
            import pdfplumber
            return True
        except ImportError:
            logger.warning("pdfplumber not available, will use fallback")
            return False

    def _check_pypdf(self) -> bool:
        """Check if pypdf is available."""
        try:
            import pypdf
            return True
        except ImportError:
            logger.warning("pypdf not available")
            return False

    def extract(self, source: Union[str, Path, bytes, io.BytesIO]) -> PDFExtractionResult:
        """
        Extract text and tables from a PDF document.

        Args:
            source: File path, bytes, or BytesIO object

        Returns:
            PDFExtractionResult with extracted content and metadata
        """
        # Convert source to appropriate format
        if isinstance(source, (str, Path)):
            file_path = Path(source)
            if not file_path.exists():
                return PDFExtractionResult(
                    success=False,
                    content="",
                    errors=[f"File not found: {file_path}"]
                )

        # Try pdfplumber first (better quality)
        if self._pdfplumber_available:
            try:
                return self._extract_with_pdfplumber(source)
            except Exception as e:
                logger.warning(f"pdfplumber extraction failed: {e}, trying fallback")
                if self._pypdf_available:
                    return self._extract_with_pypdf(source)
                raise

        # Fallback to pypdf
        if self._pypdf_available:
            return self._extract_with_pypdf(source)

        return PDFExtractionResult(
            success=False,
            content="",
            errors=["No PDF extraction library available"]
        )

    def _extract_with_pdfplumber(self, source: Union[str, Path, bytes, io.BytesIO]) -> PDFExtractionResult:
        """Extract using pdfplumber (primary method)."""
        import pdfplumber

        pages: List[ExtractedPage] = []
        all_tables: List[ExtractedTable] = []
        errors: List[str] = []
        metadata: Dict[str, Any] = {}

        # Handle different source types
        if isinstance(source, bytes):
            source = io.BytesIO(source)

        with pdfplumber.open(source) as pdf:
            metadata = {
                "pdf_version": getattr(pdf.metadata, 'pdf_version', None),
                "title": pdf.metadata.get("Title", ""),
                "author": pdf.metadata.get("Author", ""),
                "creator": pdf.metadata.get("Creator", ""),
                "producer": pdf.metadata.get("Producer", ""),
                "creation_date": str(pdf.metadata.get("CreationDate", "")),
            }

            for page_num, page in enumerate(pdf.pages, start=1):
                try:
                    # Extract text with layout preservation
                    if self.preserve_layout:
                        text = page.extract_text(layout=True) or ""
                    else:
                        text = page.extract_text() or ""

                    page_tables: List[ExtractedTable] = []

                    # Extract tables if enabled
                    if self.extract_tables:
                        try:
                            tables = page.extract_tables(self.table_settings)
                            for table_idx, table in enumerate(tables or []):
                                if table and len(table) > 0:
                                    # First row as headers if it looks like headers
                                    headers = table[0] if table else []
                                    rows = table[1:] if len(table) > 1 else []

                                    extracted_table = ExtractedTable(
                                        page_number=page_num,
                                        table_index=table_idx,
                                        headers=[str(h) if h else "" for h in headers],
                                        rows=[[str(cell) if cell else "" for cell in row] for row in rows],
                                        row_count=len(rows),
                                        column_count=len(headers)
                                    )
                                    page_tables.append(extracted_table)
                                    all_tables.append(extracted_table)
                        except Exception as e:
                            errors.append(f"Table extraction failed on page {page_num}: {str(e)}")

                    pages.append(ExtractedPage(
                        page_number=page_num,
                        text=text,
                        tables=page_tables
                    ))

                except Exception as e:
                    errors.append(f"Page {page_num} extraction failed: {str(e)}")
                    pages.append(ExtractedPage(
                        page_number=page_num,
                        text=f"[Error extracting page {page_num}]"
                    ))

        # Combine all text
        full_content = self._combine_content(pages, all_tables)

        return PDFExtractionResult(
            success=True,
            content=full_content,
            pages=pages,
            total_pages=len(pages),
            total_tables=len(all_tables),
            total_chars=sum(p.char_count for p in pages),
            total_words=sum(p.word_count for p in pages),
            metadata=metadata,
            errors=errors,
            extraction_method="pdfplumber"
        )

    def _extract_with_pypdf(self, source: Union[str, Path, bytes, io.BytesIO]) -> PDFExtractionResult:
        """Extract using pypdf (fallback method)."""
        import pypdf

        pages: List[ExtractedPage] = []
        errors: List[str] = []
        metadata: Dict[str, Any] = {}

        # Handle different source types
        if isinstance(source, bytes):
            source = io.BytesIO(source)

        reader = pypdf.PdfReader(source)

        # Extract metadata
        if reader.metadata:
            metadata = {
                "title": reader.metadata.get("/Title", ""),
                "author": reader.metadata.get("/Author", ""),
                "creator": reader.metadata.get("/Creator", ""),
                "producer": reader.metadata.get("/Producer", ""),
            }

        for page_num, page in enumerate(reader.pages, start=1):
            try:
                text = page.extract_text() or ""
                pages.append(ExtractedPage(
                    page_number=page_num,
                    text=text,
                    tables=[]  # pypdf doesn't extract tables
                ))
            except Exception as e:
                errors.append(f"Page {page_num} extraction failed: {str(e)}")
                pages.append(ExtractedPage(
                    page_number=page_num,
                    text=f"[Error extracting page {page_num}]"
                ))

        full_content = "\n\n".join(p.text for p in pages if p.text)

        return PDFExtractionResult(
            success=True,
            content=full_content,
            pages=pages,
            total_pages=len(pages),
            total_tables=0,
            total_chars=sum(p.char_count for p in pages),
            total_words=sum(p.word_count for p in pages),
            metadata=metadata,
            errors=errors,
            extraction_method="pypdf"
        )

    def _combine_content(self, pages: List[ExtractedPage], tables: List[ExtractedTable]) -> str:
        """Combine page text and tables into unified content."""
        content_parts = []

        for page in pages:
            if page.text:
                content_parts.append(f"--- Page {page.page_number} ---\n{page.text}")

            # Add tables for this page
            page_tables = [t for t in tables if t.page_number == page.page_number]
            for table in page_tables:
                md_table = table.to_markdown()
                if md_table:
                    content_parts.append(f"\n[Table {table.table_index + 1}]\n{md_table}\n")

        return "\n\n".join(content_parts)


def extract_text_from_pdf(
    source: Union[str, Path, bytes, io.BytesIO],
    extract_tables: bool = True,
    preserve_layout: bool = True
) -> Dict[str, Any]:
    """
    Convenience function to extract text from a PDF.

    Args:
        source: File path, bytes, or BytesIO object
        extract_tables: Whether to extract tables
        preserve_layout: Whether to preserve text layout

    Returns:
        Dictionary with extraction results
    """
    extractor = PDFExtractor(
        extract_tables=extract_tables,
        preserve_layout=preserve_layout
    )
    result = extractor.extract(source)
    return result.to_dict()

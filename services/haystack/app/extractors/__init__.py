"""
Document Extractors Module

Enterprise-grade document text extraction with support for:
- PDF documents (with layout preservation and table extraction)
- Word documents (.docx) with structure preservation
- Excel spreadsheets (.xlsx) with multi-sheet and table support

All extractors return structured data including:
- Raw text content
- Metadata (page counts, sheet names, etc.)
- Structural elements (tables, sections, etc.)
"""

from .pdf_extractor import PDFExtractor, extract_text_from_pdf
from .docx_extractor import DOCXExtractor, extract_text_from_docx
from .excel_extractor import ExcelExtractor, extract_text_from_excel

__all__ = [
    'PDFExtractor',
    'DOCXExtractor',
    'ExcelExtractor',
    'extract_text_from_pdf',
    'extract_text_from_docx',
    'extract_text_from_excel',
]

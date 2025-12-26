"""
Document Extractors Module

Enterprise-grade document text extraction with support for:
- PDF documents (with layout preservation and table extraction)
- Word documents (.docx, .doc) with structure preservation
- Excel spreadsheets (.xlsx, .xls) with multi-sheet and table support
- CSV files with tabular data extraction
- HTML documents with structure preservation
- reStructuredText (.rst) documents

All extractors return structured data including:
- Raw text content
- Metadata (page counts, sheet names, etc.)
- Structural elements (tables, sections, etc.)
"""

from .pdf_extractor import PDFExtractor, extract_text_from_pdf
from .docx_extractor import DOCXExtractor, extract_text_from_docx
from .excel_extractor import ExcelExtractor, extract_text_from_excel
from .csv_extractor import extract_text_from_csv
from .html_extractor import extract_text_from_html
from .rst_extractor import extract_text_from_rst

__all__ = [
    'PDFExtractor',
    'DOCXExtractor',
    'ExcelExtractor',
    'extract_text_from_pdf',
    'extract_text_from_docx',
    'extract_text_from_excel',
    'extract_text_from_csv',
    'extract_text_from_html',
    'extract_text_from_rst',
]

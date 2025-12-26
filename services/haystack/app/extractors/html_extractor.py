"""
HTML Text Extractor

Extracts text content from HTML documents, removing tags and
preserving document structure for semantic search.
"""

import io
import logging
import re
from typing import Dict, Any, Union
from pathlib import Path

logger = logging.getLogger(__name__)


def extract_text_from_html(
    source: Union[str, Path, bytes, io.BytesIO],
    include_links: bool = True,
    include_tables: bool = True,
    preserve_structure: bool = True
) -> Dict[str, Any]:
    """
    Extract text content from an HTML document.

    Args:
        source: File path, bytes, or BytesIO object
        include_links: Include link URLs in extracted text
        include_tables: Convert tables to markdown format
        preserve_structure: Preserve headings and list structure

    Returns:
        Dictionary with extraction results
    """
    try:
        # Try to import BeautifulSoup
        try:
            from bs4 import BeautifulSoup
            use_bs4 = True
        except ImportError:
            logger.warning("BeautifulSoup not available, using regex fallback")
            use_bs4 = False

        # Handle different source types
        if isinstance(source, (str, Path)):
            with open(source, 'r', encoding='utf-8', errors='replace') as f:
                html_content = f.read()
        elif isinstance(source, bytes):
            try:
                html_content = source.decode('utf-8')
            except UnicodeDecodeError:
                html_content = source.decode('latin-1')
        elif isinstance(source, io.BytesIO):
            source.seek(0)
            try:
                html_content = source.read().decode('utf-8')
            except UnicodeDecodeError:
                source.seek(0)
                html_content = source.read().decode('latin-1')
        else:
            return {
                "success": False,
                "content": "",
                "errors": ["Invalid source type"]
            }

        if use_bs4:
            result = _extract_with_beautifulsoup(
                html_content, include_links, include_tables, preserve_structure
            )
        else:
            result = _extract_with_regex(html_content)

        return result

    except Exception as e:
        logger.error(f"HTML extraction failed: {e}")
        return {
            "success": False,
            "content": "",
            "errors": [f"HTML extraction failed: {str(e)}"]
        }


def _extract_with_beautifulsoup(
    html: str,
    include_links: bool,
    include_tables: bool,
    preserve_structure: bool
) -> Dict[str, Any]:
    """Extract text using BeautifulSoup."""
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(html, 'html.parser')

    # Remove script, style, and other non-content elements
    for element in soup(['script', 'style', 'meta', 'link', 'noscript', 'header', 'footer', 'nav']):
        element.decompose()

    # Extract metadata
    title = soup.title.string if soup.title else ""
    meta_description = ""
    meta_tag = soup.find('meta', attrs={'name': 'description'})
    if meta_tag:
        meta_description = meta_tag.get('content', '')

    text_parts = []

    # Add title
    if title:
        text_parts.append(f"# {title}\n")

    # Add meta description
    if meta_description:
        text_parts.append(f"*{meta_description}*\n")

    if preserve_structure:
        # Process headings
        for level in range(1, 7):
            for heading in soup.find_all(f'h{level}'):
                heading_text = heading.get_text(strip=True)
                if heading_text:
                    heading.replace_with(f"\n{'#' * level} {heading_text}\n")

        # Process lists
        for ul in soup.find_all('ul'):
            items = []
            for li in ul.find_all('li', recursive=False):
                items.append(f"- {li.get_text(strip=True)}")
            if items:
                ul.replace_with("\n" + "\n".join(items) + "\n")

        for ol in soup.find_all('ol'):
            items = []
            for i, li in enumerate(ol.find_all('li', recursive=False), 1):
                items.append(f"{i}. {li.get_text(strip=True)}")
            if items:
                ol.replace_with("\n" + "\n".join(items) + "\n")

    if include_tables:
        # Convert tables to markdown
        for table in soup.find_all('table'):
            md_table = _table_to_markdown(table)
            if md_table:
                table.replace_with(f"\n{md_table}\n")

    if include_links:
        # Preserve link information
        for link in soup.find_all('a', href=True):
            href = link.get('href', '')
            text = link.get_text(strip=True)
            if href and text and href.startswith(('http://', 'https://')):
                link.replace_with(f"{text} ({href})")

    # Get main text content
    main_content = soup.find('main') or soup.find('article') or soup.find('body') or soup
    text = main_content.get_text(separator='\n')

    # Clean up whitespace
    lines = []
    for line in text.split('\n'):
        line = line.strip()
        if line:
            lines.append(line)

    full_content = '\n'.join(lines)

    # Collapse multiple newlines
    full_content = re.sub(r'\n{3,}', '\n\n', full_content)

    if text_parts:
        full_content = '\n'.join(text_parts) + '\n' + full_content

    return {
        "success": True,
        "content": full_content,
        "total_chars": len(full_content),
        "total_words": len(full_content.split()),
        "metadata": {
            "title": title,
            "description": meta_description
        },
        "errors": []
    }


def _extract_with_regex(html: str) -> Dict[str, Any]:
    """Fallback extraction using regex (when BeautifulSoup not available)."""
    # Remove script and style content
    html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
    html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL | re.IGNORECASE)

    # Extract title
    title_match = re.search(r'<title[^>]*>(.*?)</title>', html, re.IGNORECASE | re.DOTALL)
    title = title_match.group(1).strip() if title_match else ""

    # Remove all HTML tags
    text = re.sub(r'<[^>]+>', ' ', html)

    # Decode HTML entities
    text = re.sub(r'&nbsp;', ' ', text)
    text = re.sub(r'&lt;', '<', text)
    text = re.sub(r'&gt;', '>', text)
    text = re.sub(r'&amp;', '&', text)
    text = re.sub(r'&quot;', '"', text)
    text = re.sub(r'&#\d+;', '', text)

    # Clean up whitespace
    text = re.sub(r'\s+', ' ', text).strip()

    full_content = f"# {title}\n\n{text}" if title else text

    return {
        "success": True,
        "content": full_content,
        "total_chars": len(full_content),
        "total_words": len(full_content.split()),
        "metadata": {
            "title": title,
            "extraction_method": "regex_fallback"
        },
        "errors": []
    }


def _table_to_markdown(table) -> str:
    """Convert HTML table to markdown format."""
    rows = []

    # Get header row
    thead = table.find('thead')
    if thead:
        header_row = thead.find('tr')
        if header_row:
            headers = [th.get_text(strip=True) for th in header_row.find_all(['th', 'td'])]
            if headers:
                rows.append("| " + " | ".join(headers) + " |")
                rows.append("| " + " | ".join("---" for _ in headers) + " |")

    # Get body rows
    tbody = table.find('tbody') or table
    for tr in tbody.find_all('tr'):
        cells = [td.get_text(strip=True)[:50] for td in tr.find_all(['td', 'th'])]
        if cells:
            # Skip if this looks like the header row we already added
            if len(rows) <= 2 or cells != [c.strip() for c in rows[0].strip('|').split('|')]:
                rows.append("| " + " | ".join(cells) + " |")

    return "\n".join(rows) if len(rows) > 2 else ""

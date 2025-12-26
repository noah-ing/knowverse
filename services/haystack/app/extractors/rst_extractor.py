"""
reStructuredText (RST) Extractor

Extracts text content from RST files, converting markup
to plain text or markdown for semantic search.
"""

import io
import logging
import re
from typing import Dict, Any, Union
from pathlib import Path

logger = logging.getLogger(__name__)


def extract_text_from_rst(
    source: Union[str, Path, bytes, io.BytesIO],
    convert_to_markdown: bool = True
) -> Dict[str, Any]:
    """
    Extract text content from an RST document.

    Args:
        source: File path, bytes, or BytesIO object
        convert_to_markdown: Convert RST markup to markdown

    Returns:
        Dictionary with extraction results
    """
    try:
        # Handle different source types
        if isinstance(source, (str, Path)):
            with open(source, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
        elif isinstance(source, bytes):
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

        # Try to use docutils for proper parsing
        try:
            from docutils.core import publish_parts
            from docutils.parsers.rst import Parser
            use_docutils = True
        except ImportError:
            logger.warning("docutils not available, using regex conversion")
            use_docutils = False

        if use_docutils:
            result = _extract_with_docutils(content)
        else:
            result = _extract_with_regex(content, convert_to_markdown)

        return result

    except Exception as e:
        logger.error(f"RST extraction failed: {e}")
        return {
            "success": False,
            "content": "",
            "errors": [f"RST extraction failed: {str(e)}"]
        }


def _extract_with_docutils(rst_content: str) -> Dict[str, Any]:
    """Extract text using docutils parser."""
    from docutils.core import publish_parts

    try:
        # Convert RST to HTML, then extract text
        parts = publish_parts(
            rst_content,
            writer_name='html',
            settings_overrides={
                'report_level': 5,  # Suppress warnings
                'halt_level': 5,
                'initial_header_level': 1
            }
        )

        # Get the body content
        html_body = parts.get('body', '')

        # Simple HTML to text conversion
        text = re.sub(r'<[^>]+>', ' ', html_body)
        text = re.sub(r'\s+', ' ', text).strip()

        # Also get the title
        title = parts.get('title', '')

        full_content = f"# {title}\n\n{text}" if title else text

        return {
            "success": True,
            "content": full_content,
            "total_chars": len(full_content),
            "total_words": len(full_content.split()),
            "metadata": {
                "title": title,
                "extraction_method": "docutils"
            },
            "errors": []
        }

    except Exception as e:
        logger.warning(f"docutils parsing failed: {e}, falling back to regex")
        return _extract_with_regex(rst_content, True)


def _extract_with_regex(rst_content: str, convert_to_markdown: bool) -> Dict[str, Any]:
    """Convert RST to plain text/markdown using regex."""
    content = rst_content

    if convert_to_markdown:
        # Convert RST headings to markdown
        # RST uses underlines for headings: ===, ---, ~~~, etc.
        lines = content.split('\n')
        converted_lines = []
        i = 0

        while i < len(lines):
            line = lines[i]

            # Check for underline-style headings
            if i + 1 < len(lines):
                next_line = lines[i + 1]
                if next_line and len(next_line) >= len(line.strip()) and re.match(r'^[=\-~`\'"^_*+#]+$', next_line.strip()):
                    # This is a heading
                    heading_char = next_line.strip()[0]
                    heading_level = {'=': 1, '-': 2, '~': 3, '^': 4, '"': 5}.get(heading_char, 2)
                    converted_lines.append(f"{'#' * heading_level} {line.strip()}")
                    i += 2  # Skip the underline
                    continue

            # Check for overline+underline style headings
            if re.match(r'^[=\-~`\'"^_*+#]+$', line.strip()) and i + 2 < len(lines):
                next_line = lines[i + 1]
                after_next = lines[i + 2]
                if after_next.strip() == line.strip():
                    heading_char = line.strip()[0]
                    heading_level = {'=': 1, '-': 2}.get(heading_char, 1)
                    converted_lines.append(f"{'#' * heading_level} {next_line.strip()}")
                    i += 3
                    continue

            # Convert inline markup
            # **bold** stays the same
            # *italic* stays the same (same as markdown)
            # ``code`` -> `code`
            line = re.sub(r'``([^`]+)``', r'`\1`', line)

            # Convert RST links
            # `Link text <URL>`_ -> [Link text](URL)
            line = re.sub(r'`([^<]+)\s*<([^>]+)>`_', r'[\1](\2)', line)

            # Convert bullet lists (already compatible)
            # Convert numbered lists (already compatible)

            # Convert directives to plain text
            # .. note:: -> **Note:**
            line = re.sub(r'\.\.\s+note::', '**Note:**', line)
            line = re.sub(r'\.\.\s+warning::', '**Warning:**', line)
            line = re.sub(r'\.\.\s+tip::', '**Tip:**', line)
            line = re.sub(r'\.\.\s+important::', '**Important:**', line)

            # Remove other directives but keep content
            line = re.sub(r'\.\.\s+\w+::', '', line)

            converted_lines.append(line)
            i += 1

        content = '\n'.join(converted_lines)

    # Clean up
    content = re.sub(r'\n{3,}', '\n\n', content)  # Collapse multiple newlines
    content = content.strip()

    return {
        "success": True,
        "content": content,
        "total_chars": len(content),
        "total_words": len(content.split()),
        "metadata": {
            "extraction_method": "regex_conversion"
        },
        "errors": []
    }

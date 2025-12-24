# KnowVerse User Guide

Welcome to KnowVerse, your enterprise knowledge management and AI-powered search platform.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Uploading Documents](#uploading-documents)
3. [Searching Your Knowledge Base](#searching-your-knowledge-base)
4. [RAG Chat (AI Assistant)](#rag-chat-ai-assistant)
5. [Connectors (Google Drive, Notion)](#connectors)
6. [SSO Login](#sso-login)

---

## Getting Started

### Creating an Account

1. Visit your organization's KnowVerse instance
2. Click "Sign Up" or request access from your administrator
3. Enter your email address
4. Click the magic link sent to your inbox

### Joining an Organization

After signing up, your administrator will invite you to your organization. You'll receive an email with a link to accept the invitation.

---

## Uploading Documents

### Supported File Types

| Format | Extensions |
|--------|------------|
| PDF | .pdf |
| Microsoft Word | .docx, .doc |
| Text | .txt, .md, .rtf |
| Excel | .xlsx, .xls, .csv |

### Single File Upload

1. Navigate to **Documents** in the sidebar
2. Click **Upload Document**
3. Select a file from your computer
4. Wait for processing to complete

### Batch Upload

1. Navigate to **Documents**
2. Drag and drop multiple files onto the upload area
3. Review the files to upload
4. Click **Upload All**
5. Monitor progress in the status bar

### Document Processing

After upload, documents go through:
1. **Text Extraction** - Content is extracted from the file
2. **Chunking** - Text is split into semantic chunks
3. **Embedding** - Each chunk is converted to a vector
4. **Indexing** - Vectors are indexed for fast search

Processing typically takes 30-60 seconds per document.

---

## Searching Your Knowledge Base

### Basic Search

1. Navigate to **Search** in the sidebar
2. Enter your query in natural language
3. Press Enter or click Search

### Search Tips

- **Be specific**: "Q4 2024 revenue" works better than "revenue"
- **Use natural language**: "What were our sales last quarter?"
- **Include context**: "Marketing budget for the APAC region"

### Search Filters

- **Document Type**: Filter by PDF, Word, etc.
- **Date Range**: Limit to recently uploaded documents
- **Time Period**: Filter by document content dates

### Understanding Results

Each result shows:
- **Document title** and type
- **Relevance score** (0-100%)
- **Content preview** with highlighted matches
- **Chunk location** within the document

---

## RAG Chat (AI Assistant)

### Starting a Conversation

1. Navigate to **RAG Chat** in the sidebar
2. Type your question in the chat input
3. Press Enter to send

### Chat Modes

| Mode | Best For |
|------|----------|
| **Standard** | Quick questions with direct answers |
| **Agent** | Complex queries requiring reasoning |
| **Deep Research** | Multi-document investigation |
| **Plan-Execute** | Step-by-step analysis tasks |

### Understanding Citations

Responses include inline citations `[1]` `[2]` that link to source documents:

- **Hover** over a citation to see a preview
- **Click** a citation to open the source document
- The specific chunk will be highlighted

### Source Pills

Below each response, you'll see source pills showing:
- Document title
- Chunk number (e.g., "3/12" means chunk 3 of 12)
- Relevance score

---

## Connectors

### Google Drive

Connect your Google Drive to automatically sync documents:

1. Navigate to **Documents** > **Connectors** > **Google Drive**
2. Click **Connect Google Drive**
3. Sign in with your Google account
4. Grant permissions to access Drive
5. Select folders to sync (optional)
6. Click **Start Sync**

**Synced file types**: PDF, Google Docs, Google Sheets, Word

### Notion

Connect your Notion workspace:

1. Navigate to **Documents** > **Connectors** > **Notion**
2. Click **Connect Notion**
3. Select the workspace and pages to share
4. Grant access permissions
5. Click **Start Sync**

**Synced content**: Pages and databases with text content

### Managing Synced Content

- View sync status in the connector dashboard
- Manually trigger re-sync with **Sync Now**
- Disconnect to stop syncing (documents remain)

---

## SSO Login

If your organization uses Single Sign-On:

### Logging In

1. Go to `/sso` on your KnowVerse instance
2. Enter your organization name or work email
3. Click **Continue with SSO**
4. You'll be redirected to your identity provider
5. Complete authentication
6. You're automatically logged in

### Direct SSO URL

Bookmark your organization's SSO URL for quick access:
```
https://knowverse.app/sso/your-org-slug
```

### Troubleshooting SSO

| Issue | Solution |
|-------|----------|
| "SSO not enabled" | Contact your organization admin |
| "Email domain not allowed" | Use your work email address |
| "User not provisioned" | Contact admin to enable auto-provisioning |

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `/` | Focus search |
| `Cmd/Ctrl + K` | Quick search |
| `Cmd/Ctrl + N` | New document |
| `Esc` | Close modal/panel |

---

## Getting Help

- **Documentation**: `/docs`
- **Contact Admin**: Settings > Support
- **Report Issue**: Settings > Feedback

---

*For administrator documentation, see [Admin Guide](../admin/README.md).*
*For API documentation, see [API Reference](../api/README.md).*

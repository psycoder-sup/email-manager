# Cluademail - Product Requirements Document

## Overview

Cluademail is a native macOS desktop email client with built-in MCP (Model Context Protocol) server integration. It enables AI assistants like Claude to read, analyze, search, and draft email replies programmatically while giving users full control over their email workflow.

## Problem Statement

Managing multiple email accounts is time-consuming. AI assistants can help summarize emails, identify important messages, and draft replies—but they lack direct access to email data. Existing email clients don't expose an interface for AI integration.

Cluademail solves this by providing a full-featured email client with an MCP server that allows AI tools (Claude Code, Claude Desktop) to interact with emails securely and locally.

## Target Users

Individual professionals who:
- Manage 3+ Gmail accounts
- Want AI assistance for email triage, summarization, and reply drafting
- Use Claude Code or Claude Desktop
- Prefer native macOS applications

## Product Goals

1. Provide a polished, native macOS email experience
2. Enable seamless AI integration through MCP
3. Keep all data local—no external backend servers
4. Give users full control over email sending (AI can draft, user confirms)

---

## Features

### Email Client Features

#### Account Management
- Support for multiple Gmail accounts (3+)
- Google OAuth 2.0 authentication
- Gmail API and IMAP/SMTP support
- Add/remove accounts via Settings

#### Email Views
- **Aggregated Inbox**: All accounts combined, sorted by date
- **Per-account tabs/spaces**: Filter to view single account's emails
- **Folders**: Inbox, Sent, Drafts, Trash, Spam, Starred/Flagged
- **Threading**: Conversations grouped as threads
- **Email display**: Show account name, sender, subject, and received date

#### Email Actions
- Read emails with full content and attachments
- Compose new emails
- Reply / Reply All / Forward
- Mark as read/unread
- Star/Unstar
- Archive
- Move to Trash/Spam
- View and apply existing Gmail labels (no create/edit/delete)

#### Composing
- Auto-select sending account based on the email being replied to
- Attachment support (view and send)
- Rich text / HTML email support

#### Search
- In-app search bar
- Search by keyword, sender, subject, date range

#### Sync & Notifications
- Sync last 1,000 emails per account
- Background sync interval: 5 minutes (user configurable)
- Native macOS notifications for new emails
- Optional: Local caching for performance (can be deferred)

---

### MCP Integration

#### Transport
- **stdio**: Claude Code spawns the MCP server as a subprocess

#### MCP Tools

| Tool | Description |
|------|-------------|
| `list_emails` | List emails with filters (unread, date range, sender, account, folder) |
| `read_email` | Get full content of a specific email by ID |
| `search_emails` | Search emails by query string |
| `create_draft` | Create a draft reply or new email (must specify account) |
| `manage_labels` | Add or remove labels from an email |
| `get_attachment` | Download/read attachment content for analysis |

#### MCP Constraints
- **No send capability**: AI can only create drafts; user must manually confirm and send
- **Local-only**: MCP server only accepts local connections
- **Account specification**: Draft creation requires explicit account selection

---

## Technical Requirements

### Platform
- macOS desktop application
- Native Swift / SwiftUI

### Authentication
- Google OAuth 2.0 for Gmail access
- Secure token storage in macOS Keychain

### Email Protocols
- Gmail API (primary)
- IMAP/SMTP as fallback

### Data Storage
- Local database for email cache and metadata
- Last 1,000 emails per account
- Attachments downloaded on demand

### MCP Server
- Built-in MCP server (stdio transport)
- Runs when application is open
- Follows MCP specification

---

## User Interface

### Main Window Layout
- **Sidebar**: Account list, folder navigation (Inbox, Sent, Drafts, etc.)
- **Email List**: Threaded conversations, shows account indicator
- **Reading Pane**: Full email content with attachments
- **Compose Window**: Modal or separate window for composing

### Settings Screen
- Account management (add/remove Gmail accounts)
- Sync frequency configuration
- MCP server toggle (on/off)

### Visual Indicators
- Account name badge on each email in aggregated view
- Unread count per folder
- Sync status indicator

---

## Security

- All data stored locally on user's machine
- No external backend servers
- OAuth tokens stored in macOS Keychain
- MCP server accepts local connections only
- No automatic email sending—user must confirm all outgoing emails

---

## Out of Scope (v1)

- Per-account email signatures
- Offline mode (beyond local caching)
- Cross-platform support (Windows, Linux)
- Calendar integration
- Contact management
- Custom label creation/editing
- Keyboard shortcuts customization
- Email rules/filters automation
- Multiple email providers (Outlook, Yahoo, etc.)

---

## Future Considerations

- Full offline support with sync queue
- Additional email providers (Outlook, IMAP generic)
- Smart categorization and priority inbox
- Email templates
- Scheduled sending
- Enhanced caching system
- Keyboard shortcuts

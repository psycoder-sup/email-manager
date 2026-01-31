# Task 12: MCP Server Integration

## Task Overview

Implement the MCP (Model Context Protocol) server that enables AI assistants like Claude to interact with emails through stdio transport. This includes all 6 MCP tools defined in the PRD.

## Dependencies

- Task 01: Project Setup & Architecture
- Task 02: Core Data Models
- Task 03: Local Database Layer
- Task 05: Gmail API Service
- Task 06: Email Sync Engine

## Architectural Guidelines

### Design Patterns
- **Command Pattern**: Each MCP tool as a command handler
- **Factory Pattern**: Tool creation and registration
- **Protocol-Based**: Define clear tool interfaces

### SwiftUI/Swift Conventions
- Use structured concurrency for tool execution
- Use Codable for JSON-RPC serialization
- Handle process lifecycle properly

### File Organization
```
MCP/
├── Server/
│   ├── MCPServer.swift
│   ├── MCPProtocol.swift
│   ├── StdioTransport.swift
│   ├── JSONRPCHandler.swift
│   ├── MCPServerProcess.swift     # Spawns MCP server as subprocess
│   ├── MCPConnectionManager.swift # Handles concurrent clients
│   └── MCPRateLimiter.swift       # Rate limiting for AI requests
├── Tools/
│   ├── MCPTool.swift
│   ├── ListEmailsTool.swift
│   ├── ReadEmailTool.swift
│   ├── SearchEmailsTool.swift
│   ├── CreateDraftTool.swift
│   ├── ManageLabelsTool.swift
│   └── GetAttachmentTool.swift
├── Models/
│   ├── MCPRequest.swift
│   ├── MCPResponse.swift
│   └── MCPError.swift
└── Logging/
    └── MCPLogger.swift            # MCP-specific logging
```

## Implementation Details

### JSON-RPC 2.0 Protocol

**Request Structure**:
```json
{
  "jsonrpc": "2.0",
  "method": "method_name",
  "params": { ... },
  "id": 1
}
```

**Response Structure** (success):
```json
{
  "jsonrpc": "2.0",
  "result": { ... },
  "id": 1
}
```

**Response Structure** (error):
```json
{
  "jsonrpc": "2.0",
  "error": { "code": -32600, "message": "Invalid Request" },
  "id": 1
}
```

**Standard Error Codes**:
| Code | Meaning |
|------|---------|
| -32700 | Parse error |
| -32600 | Invalid Request |
| -32601 | Method not found |
| -32602 | Invalid params |
| -32603 | Internal error |

**JSONRPCId**:
- Can be string, int, or null
- Use enum with Codable for flexible parsing

---

### MCP Protocol Messages

**Initialize Request**:
- Method: `initialize`
- Params: protocolVersion, capabilities, clientInfo (name, version)

**Initialize Response**:
- Result: protocolVersion ("2024-11-05"), capabilities (tools), serverInfo (name, version)

**Tools List Request**:
- Method: `tools/list`

**Tools List Response**:
- Result: tools array with name, description, inputSchema

**Tool Call Request**:
- Method: `tools/call`
- Params: name, arguments

**Tool Call Response**:
- Result: content array with type="text" and text result

---

### MCPServer

**Purpose**: Main server orchestrating MCP protocol
**Type**: `@Observable` class

**Properties**:
- `isRunning`: Bool
- `connectedClients`: Int

**Dependencies**:
- StdioTransport
- MCPToolRegistry (with all tools)

**Lifecycle**:
- `start()`: Set isRunning, launch async server loop
- `stop()`: Set isRunning=false, close transport

**Server Loop**:
1. While isRunning: read message from transport
2. Handle EOF (client disconnect) - break loop
3. Parse and handle message
4. Write response to transport

**Message Handling**:
- `initialize`: Return server info and capabilities
- `initialized`: No response (notification)
- `shutdown`: Decrement clients, return empty result
- `tools/list`: Return tool schemas from registry
- `tools/call`: Execute tool, return result or error

---

### StdioTransport

**Purpose**: Read/write JSON-RPC over stdio
**Type**: Actor (thread-safe)

**Message Framing**:
- Header: `Content-Length: {length}\r\n\r\n`
- Body: JSON content

**Public Interface**:
- `readMessage() async throws -> Data?`
- `writeMessage(_:) async throws`
- `close()`

**Read Flow**:
1. Read header line (readLine())
2. Parse Content-Length value
3. Read empty line
4. Read exactly {length} bytes

**Write Flow**:
1. Build header with content length
2. Write header to stdout
3. Write body to stdout

---

### MCPToolProtocol

**Purpose**: Interface for all MCP tools
**Type**: Protocol

**Requirements**:
- `name`: String
- `description`: String
- `schema`: MCPTool (JSON schema)
- `execute(arguments:) async throws -> String`

---

### MCPToolError

**Purpose**: Tool-specific errors
**Type**: Struct with code and message

**Factory Methods**:
- `invalidParameter(_:)` - Missing/invalid parameter (-32602)
- `notFound(_:)` - Resource not found (-32001)
- `accountRequired()` - No account specified (-32002)

---

### MCPToolRegistry

**Purpose**: Register and lookup tools
**Type**: Class

**Methods**:
- `init(tools:)` - Register tools by name
- `listTools() -> [MCPToolProtocol]`
- `getTool(name:) -> MCPToolProtocol?`

---

### Tool: list_emails

**Purpose**: List emails with optional filters

**Input Schema**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| account | string | Yes | Email address of account |
| folder | string | No | Folder (inbox, sent, drafts, trash, spam, starred) |
| unread_only | boolean | No | Only return unread |
| limit | integer | No | Max results (default 20, max 100) |
| sender | string | No | Filter by sender email |

**Execution**:
1. Validate account parameter
2. Fetch account from repository
3. Map folder string to Folder enum
4. Fetch emails with filters
5. Optional sender filter post-fetch
6. Format output with email details

**Output Format**:
```
Found N emails:

ID: {gmailId}
From: {name} <{email}>
Subject: {subject}
Date: {date}
Unread: {true/false}
Starred: {true/false}
---
```

---

### Tool: read_email

**Purpose**: Get full content of specific email

**Input Schema**:
| Parameter | Type | Required |
|-----------|------|----------|
| email_id | string | Yes |
| account | string | Yes |

**Execution**:
1. Validate parameters
2. Fetch email by gmailId
3. Verify email belongs to specified account
4. Format full content

**Output Format**:
```
ID: {gmailId}
Thread ID: {threadId}
From: {name} <{email}>
To: {recipients}
Cc: {recipients} (if any)
Subject: {subject}
Date: {date}
Labels: {labels}

--- Body ---
{body text or html fallback or snippet}

--- Attachments --- (if any)
- {filename} ({size}, {mimeType})
```

---

### Tool: search_emails

**Purpose**: Search emails by query

**Input Schema**:
| Parameter | Type | Required |
|-----------|------|----------|
| query | string | Yes |
| account | string | Yes |
| limit | integer | No |

**Execution**:
1. Validate parameters
2. Fetch account
3. Search via repository
4. Limit results (default 20, max 50)
5. Format search results

**Output Format**:
```
Search results for "{query}": N emails

ID: {gmailId}
From: {name}
Subject: {subject}
Date: {date}
Snippet: {snippet truncated to 100 chars}...
---
```

---

### Tool: create_draft

**Purpose**: Create draft email (AI CANNOT send directly)

**Input Schema**:
| Parameter | Type | Required |
|-----------|------|----------|
| account | string | Yes |
| to | array[string] | Yes |
| cc | array[string] | No |
| subject | string | Yes |
| body | string | Yes |
| reply_to_id | string | No |

**Execution**:
1. Validate parameters
2. Fetch account
3. Create draft via GmailAPIService
4. Return confirmation with draft ID

**Output Format**:
```
Draft created successfully!

Draft ID: {id}
To: {recipients}
Subject: {subject}

Note: The user must manually review and send this draft from the Cluademail app or Gmail.
```

**Security Note**: This tool creates drafts only. Actual sending requires user confirmation in the UI.

---

### Tool: manage_labels

**Purpose**: Add or remove labels from email

**Input Schema**:
| Parameter | Type | Required |
|-----------|------|----------|
| email_id | string | Yes |
| account | string | Yes |
| add_labels | array[string] | No |
| remove_labels | array[string] | No |

**Execution**:
1. Validate parameters (at least one of add/remove required)
2. Fetch account
3. Call modifyMessage via GmailAPIService
4. Update local email.labelIds
5. Return confirmation

**Output Format**:
```
Labels updated for email {id}:
Added: {labels} (if any)
Removed: {labels} (if any)
```

---

### Tool: get_attachment

**Purpose**: Download and read attachment content

**Input Schema**:
| Parameter | Type | Required |
|-----------|------|----------|
| email_id | string | Yes |
| attachment_id | string | Yes |
| account | string | Yes |

**Execution**:
1. Validate parameters
2. Fetch account
3. Get attachment metadata from email
4. Download attachment data via GmailAPIService
5. Handle content based on MIME type

**Output Format**:
```
Attachment: {filename}
Size: {displaySize}
Type: {mimeType}

--- Content ---
{text content for text/* or application/json}
[PDF content - N bytes. Use a PDF viewer to read.]
[Image file - N bytes. Base64 available on request.]
[Binary file - N bytes]
```

---

### Server Process Architecture

**Decision: Embedded Helper Tool (Recommended)**

The MCP server runs as a separate command-line tool bundled with the app, not inline in the GUI process.

**Why Separate Process**:
- Claude Code spawns MCP servers as subprocesses via stdio
- GUI app cannot directly accept stdio from Claude
- Separate binary allows clean process management
- Crash isolation: server crash doesn't affect GUI

**MCPServerProcess (CLI Tool)**:
- Location: `Cluademail.app/Contents/MacOS/cluademail-mcp`
- Standalone executable that:
  1. Loads shared database (SwiftData store in Application Support)
  2. Uses stored OAuth tokens from Keychain
  3. Runs MCP server loop on stdio
  4. Exits when stdin closes

**Build Configuration**:
- Separate target in Xcode project: "CluademailMCP" (Command Line Tool)
- Shares Core/ modules with main app via shared framework or source files
- Link as embedded helper tool in main app target
- Copy Files build phase: destination "Executables"

**Database Path Resolution**:
```swift
struct MCPConfiguration {
    /// Shared database location - must match main app
    static var databaseURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Cluademail", isDirectory: true)
            .appendingPathComponent("Cluademail.store")
    }

    /// Verify database exists before starting server
    static func validateDatabaseExists() throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw MCPError.databaseNotFound(
                "Database not found. Please launch Cluademail app first to initialize."
            )
        }
    }
}
```

**Database Not Found Handling**:
- If database doesn't exist, return JSON-RPC error:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32001,
    "message": "Cluademail database not found. Please launch the Cluademail app first to set up your accounts."
  },
  "id": 1
}
```

**Claude Code Configuration** (`~/.claude/settings.json`):
```json
{
  "mcpServers": {
    "cluademail": {
      "command": "/Applications/Cluademail.app/Contents/MacOS/cluademail-mcp",
      "args": []
    }
  }
}
```

---

### Keychain Access Group Configuration

**Problem**: CLI tool needs to read OAuth tokens stored by main app

**Solution**: Shared Keychain Access Group

**Entitlements Setup**:

Both main app and CLI tool need matching entitlements:

**Cluademail.entitlements** (main app):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>keychain-access-groups</key>
    <array>
        <string>$(TeamIdentifierPrefix)com.cluademail.shared</string>
    </array>
</dict>
</plist>
```

**CluademailMCP.entitlements** (CLI tool):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>keychain-access-groups</key>
    <array>
        <string>$(TeamIdentifierPrefix)com.cluademail.shared</string>
    </array>
</dict>
</plist>
```

**KeychainService Update**:
```swift
class KeychainService {
    private let accessGroup = "$(TeamIdentifierPrefix)com.cluademail.shared"

    func save<T: Codable>(_ item: T, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.cluademail.tokens",
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,  // Shared access group
            kSecValueData as String: try JSONEncoder().encode(item)
        ]
        // ... rest of implementation
    }

    func retrieve<T: Codable>(_ type: T.Type, forKey key: String) throws -> T {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.cluademail.tokens",
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,  // Shared access group
            kSecReturnData as String: true
        ]
        // ... rest of implementation
    }
}
```

**Signing Requirements**:
- Both binaries MUST be signed with same Team ID
- Both MUST have Keychain Sharing capability enabled
- Access group prefix is automatically added by Xcode

---

### Inter-Process Database Access

**File Coordination for SwiftData**:

SwiftData uses SQLite internally, which has its own locking. However, for safety:

```swift
actor MCPDatabaseService {
    private let fileCoordinator = NSFileCoordinator()
    private let databaseURL: URL

    func performRead<T>(_ operation: (ModelContext) throws -> T) async throws -> T {
        var result: T?
        var coordinatorError: NSError?

        fileCoordinator.coordinate(
            readingItemAt: databaseURL,
            options: .withoutChanges,
            error: &coordinatorError
        ) { url in
            do {
                let container = try ModelContainer(for: schema, configurations: config)
                let context = ModelContext(container)
                result = try operation(context)
            } catch {
                // Handle error
            }
        }

        if let error = coordinatorError {
            throw MCPError.databaseAccessFailed(error.localizedDescription)
        }

        return result!
    }
}
```

**SQLite WAL Mode**:
- SwiftData uses WAL (Write-Ahead Logging) by default
- Allows concurrent readers with single writer
- MCP server is read-heavy, rarely writes (only for draft creation via API)

**Conflict Handling**:
- If main app is syncing while MCP reads: MCP sees consistent snapshot
- If MCP creates draft while app syncing: Both use same Gmail API, no conflict

---

### Main App Not Running Scenario

**Problem**: User may invoke MCP server without main app running

**Scenarios & Handling**:

| Scenario | Handling |
|----------|----------|
| Database doesn't exist | Return error: "Launch Cluademail app first" |
| Database exists but empty (no accounts) | Return error: "No accounts configured" |
| Database exists with accounts | Normal operation |
| OAuth tokens expired | Attempt refresh; if fails, return auth error |
| Main app running | Normal operation (concurrent access OK) |

**Startup Validation**:
```swift
@main
struct CluademailMCPMain {
    static func main() async {
        do {
            // 1. Validate database exists
            try MCPConfiguration.validateDatabaseExists()

            // 2. Check for configured accounts
            let accounts = try await loadAccounts()
            guard !accounts.isEmpty else {
                exitWithError(.noAccountsConfigured)
                return
            }

            // 3. Validate at least one account has valid tokens
            var hasValidAccount = false
            for account in accounts {
                if let tokens = try? tokenManager.getTokens(for: account.email),
                   !tokens.isExpired || (try? await refreshToken(for: account)) != nil {
                    hasValidAccount = true
                    break
                }
            }

            guard hasValidAccount else {
                exitWithError(.allTokensExpired)
                return
            }

            // 4. Start MCP server
            let server = MCPServer()
            try await server.run()

        } catch {
            exitWithError(.initialization(error))
        }
    }
}
```

**Auth Error Response**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32002,
    "message": "Authentication required. Please open Cluademail and sign in to your account."
  },
  "id": 1
}
```

---

### Concurrent Connection Handling

**Problem**: Multiple Claude instances may connect simultaneously

**MCPConnectionManager**:
- Track active connections: `[UUID: MCPConnection]`
- Each connection has independent state
- Limit max concurrent connections (default: 5)

**Connection Lifecycle**:
```swift
struct MCPConnection {
    let id: UUID
    let startTime: Date
    let transport: StdioTransport
    var requestCount: Int
    var isInitialized: Bool
}
```

**Concurrency Handling**:
- Each `cluademail-mcp` process handles one client
- Claude spawns multiple processes for parallel sessions
- Database access coordinated via SwiftData/SQLite locking

**Connection Limits**:
- Reject new connections if at limit with error:
  ```json
  {"error": {"code": -32000, "message": "Max connections reached"}}
  ```

---

### Version Compatibility

**Problem**: CLI tool and main app may have different versions after partial update

**Schema Version Tracking**:

Store schema version in database metadata:

```swift
// In main app's DatabaseService
struct DatabaseMetadata {
    static let currentSchemaVersion = 1
    static let metadataKey = "cluademail_schema_version"
}

func initializeDatabase() throws {
    // Store version on first launch or migration
    UserDefaults.standard.set(
        DatabaseMetadata.currentSchemaVersion,
        forKey: DatabaseMetadata.metadataKey
    )
}
```

**CLI Version Check**:
```swift
struct MCPVersionCheck {
    static let supportedSchemaVersions: ClosedRange<Int> = 1...1  // Update on migrations

    static func validateCompatibility() throws {
        let storedVersion = UserDefaults.standard.integer(
            forKey: DatabaseMetadata.metadataKey
        )

        guard storedVersion > 0 else {
            throw MCPError.databaseNotInitialized
        }

        guard supportedSchemaVersions.contains(storedVersion) else {
            throw MCPError.incompatibleVersion(
                stored: storedVersion,
                supported: supportedSchemaVersions
            )
        }
    }
}
```

**Incompatible Version Response**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32003,
    "message": "Database schema version mismatch. Please update Cluademail app to the latest version."
  },
  "id": 1
}
```

**Version in Server Info**:
Include version in initialize response for debugging:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "protocolVersion": "2024-11-05",
    "serverInfo": {
      "name": "cluademail-mcp",
      "version": "1.0.0"
    },
    "capabilities": { "tools": {} },
    "_debug": {
      "schemaVersion": 1,
      "appBundleVersion": "1.0.0"
    }
  },
  "id": 1
}
```

**Migration Strategy**:
- CLI tool is read-only for schema (never migrates)
- Main app performs migrations on launch
- If CLI detects newer schema: prompt user to update CLI (reinstall app)
- If CLI detects older schema: prompt user to launch main app to migrate

---

### Server Crash Recovery

**MCPServerProcess Crash Handling**:

**Graceful Shutdown**:
- Handle SIGTERM, SIGINT signals
- Flush pending responses
- Close database connections cleanly

**Crash Detection** (from GUI perspective):
- Not directly monitored (Claude manages subprocess)
- GUI shows "MCP Available" based on binary existence

**Auto-Restart**:
- Not applicable: Claude spawns on demand
- Each Claude session starts fresh process

**Crash Logging**:
- Write crash info to `~/Library/Logs/Cluademail/mcp-server.log`
- Include: timestamp, last request, error message
- Rotate logs (keep last 5, max 1MB each)

**Error Recovery in Server**:
- Wrap tool execution in try/catch
- Return JSON-RPC error on exception (don't crash)
- Log stack trace for debugging

---

### Large Attachment Handling

**Problem**: Base64 in JSON bloats size 33%, large files cause memory issues

**Size Limits**:
| Size | Handling |
|------|----------|
| <1MB | Return full base64 in response |
| 1-10MB | Stream to temp file, return file path |
| >10MB | Reject with error message |

**Streaming Response** (for 1-10MB):
```
Attachment: {filename}
Size: {displaySize}
Type: {mimeType}

--- Content ---
[Large file saved to: /tmp/cluademail-attachments/{uuid}_{filename}]
[File will be deleted in 1 hour]
```

**Temp File Management**:
- Store in: `NSTemporaryDirectory()/cluademail-attachments/`
- Filename: `{uuid}_{original_filename}`
- Auto-delete after 1 hour via dispatch timer
- Clean up on server shutdown

**Binary Content Strategies**:
| MIME Type | Strategy |
|-----------|----------|
| text/* | Return as UTF-8 string |
| application/json | Return parsed/formatted |
| application/pdf | Return "[PDF file - open in viewer]" |
| image/* | Return "[Image - {width}x{height}]" with dimensions if parseable |
| Other | Return "[Binary file - {size}]" |

---

### Rate Limiting

**Purpose**: Prevent AI from overwhelming email API

**MCPRateLimiter**:
```swift
actor MCPRateLimiter {
    let maxRequestsPerMinute: Int = 60
    let maxRequestsPerHour: Int = 500

    func checkLimit() async throws
    func recordRequest()
}
```

**Limits** (per MCP process):
| Window | Limit | Action on Exceed |
|--------|-------|------------------|
| Per minute | 60 requests | Return rate limit error |
| Per hour | 500 requests | Return rate limit error |
| Per tool call | 30 second timeout | Timeout error |

**Rate Limit Error**:
```json
{
  "error": {
    "code": -32029,
    "message": "Rate limit exceeded. Try again in 45 seconds."
  }
}
```

**Tool-Specific Limits**:
| Tool | Limit | Reason |
|------|-------|--------|
| list_emails | 20/min | Pagination should be used |
| read_email | 30/min | Normal reading pace |
| search_emails | 10/min | Expensive operation |
| create_draft | 10/min | Prevent spam |
| get_attachment | 20/min | Network intensive |

---

### MCP Logging & Debugging

**MCPLogger**:
- Subsystem: `com.cluademail.mcp`
- Categories: `server`, `transport`, `tools`, `errors`

**Log Levels**:
- **Debug**: Full request/response JSON (dev only)
- **Info**: Request method, tool name, duration
- **Warning**: Rate limits, validation failures
- **Error**: Crashes, API failures

**Log File Location**:
- `~/Library/Logs/Cluademail/mcp-server.log`

**Debug Mode**:
- Environment variable: `CLUADEMAIL_MCP_DEBUG=1`
- Enables verbose logging to stderr
- Useful for troubleshooting with Claude Code

**Request Tracing**:
- Each request gets UUID
- Log: `[{uuid}] {method} started`
- Log: `[{uuid}] {method} completed in {ms}ms`

**Health Check Tool** (internal, not exposed):
- Method: `debug/health`
- Returns: uptime, request count, memory usage
- Only available in debug mode

---

### Key Considerations

- **Security**: AI can ONLY create drafts, never send directly
- **Account Selection**: All operations require explicit account parameter
- **Error Messages**: Return helpful, specific error messages
- **JSON-RPC 2.0**: Follow spec strictly for compatibility
- **Stdio Handling**: Handle EOF gracefully (client disconnect)
- **Process Lifecycle**: Separate CLI tool spawned by Claude, not GUI subprocess
- **Concurrent Access**: Multiple Claude sessions can run simultaneously
- **Rate Limiting**: Prevent API abuse with per-minute/hour limits
- **Large Attachments**: Stream to temp file for >1MB, reject >10MB
- **Logging**: Dedicated MCP log file for debugging

## Acceptance Criteria

- [ ] MCP server binary bundled at `Contents/MacOS/cluademail-mcp`
- [ ] Server responds to `initialize` with capabilities
- [ ] Server responds to `tools/list` with all 6 tools
- [ ] `list_emails` returns emails with filters working
- [ ] `read_email` returns full email content
- [ ] `search_emails` searches local and returns results
- [ ] `create_draft` creates draft (does NOT send)
- [ ] `manage_labels` adds/removes labels
- [ ] `get_attachment` downloads and returns attachment content
- [ ] All tools require account parameter
- [ ] Invalid parameters return proper errors
- [ ] JSON-RPC 2.0 protocol is followed correctly
- [ ] Stdio transport reads/writes correctly
- [ ] Server handles client disconnect gracefully
- [ ] Server status shows in Settings (based on binary availability)
- [ ] **Separate CLI binary** runs independently of GUI app
- [ ] **Database path** resolved to Application Support/Cluademail/
- [ ] **Database not found** returns helpful error message
- [ ] **No accounts** returns error prompting user to configure
- [ ] **Keychain access group** shared between app and CLI (`com.cluademail.shared`)
- [ ] **Both binaries signed** with same Team ID for Keychain sharing
- [ ] **OAuth tokens** accessible from CLI via shared Keychain
- [ ] **Expired tokens** trigger refresh attempt before failing
- [ ] **Schema version** validated on CLI startup
- [ ] **Version mismatch** returns error with upgrade instructions
- [ ] **File coordination** used for cross-process database safety
- [ ] **Shared database access** works with file coordination
- [ ] **Rate limiting** enforced (60/min, 500/hour defaults)
- [ ] **Large attachments** (>1MB) saved to temp file with expiry
- [ ] **Attachments >10MB** rejected with clear error
- [ ] **MCP logs** written to ~/Library/Logs/Cluademail/mcp-server.log
- [ ] **Crash handling** logs error and exits cleanly
- [ ] **SIGTERM/SIGINT** handled for graceful shutdown

## References

- [MCP Specification](https://spec.modelcontextprotocol.io)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [MCP Tools](https://spec.modelcontextprotocol.io/specification/server/tools/)
- [stdio Transport](https://spec.modelcontextprotocol.io/specification/basic/transports/#stdio)

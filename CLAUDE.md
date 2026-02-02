# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cluademail is a native macOS email client (macOS 14.0+) built with Swift 5.9 and SwiftUI for managing multiple Gmail accounts. It features MCP (Model Context Protocol) server integration to enable AI assistants to read, search, and draft emails while users maintain control over sending.

## Build & Test Commands

```bash
# Build the project
xcodebuild -scheme Cluademail -destination "platform=macOS" build

# Run all tests
xcodebuild -scheme Cluademail -destination "platform=macOS" test

# Run a single test file (example)
xcodebuild -scheme Cluademail -destination "platform=macOS" test -only-testing:CluademailTests/AccountTests

# Run a single test method
xcodebuild -scheme Cluademail -destination "platform=macOS" test -only-testing:CluademailTests/AccountTests/testAccountInitialization
```

The project uses XcodeGen with `project.yml` for reproducible builds. If you modify targets or dependencies, regenerate with `xcodegen generate`.

## Architecture

**Pattern**: MVVM + Repository with structured concurrency and actor-based isolation.

```
Cluademail/
├── App/           # Entry point, AppState (@Observable), AppConfiguration, AppDelegate
├── Core/
│   ├── Models/    # SwiftData @Model classes (Account, Email, EmailThread, Attachment, Label, SyncState)
│   ├── Errors/    # AppError protocol + typed errors (AuthError, SyncError, APIError)
│   ├── Logging/   # Category-based loggers with privacy-aware helpers
│   ├── Repositories/  # Data access layer (protocol-based)
│   └── Services/      # Business logic
├── Features/      # Feature modules (Accounts, EmailList, EmailDetail, Compose, Search, Settings)
└── MCP/           # MCP server and tools (list_emails, read_email, search_emails, etc.)
```

## Key Patterns

**State Management**: Use `@Observable` macro with `@MainActor` isolation for UI state. Global state lives in `AppState`.

**Error Handling**: Return typed errors (`AuthError`, `SyncError`, `APIError`) implementing `AppError` protocol. Each error has `errorCode` (format: "DOMAIN_NNN"), `isRecoverable`, `errorDescription`, and `recoverySuggestion`.

**Logging**: Use category-specific loggers from `Logger+Extensions.swift`:
```swift
Logger.auth.info("User logged in")
Logger.sync.error("Sync failed: \(error.localizedDescription)")
Logger.api.logRequest(url, method: "GET")  // Privacy-aware helper
```
Categories: `app`, `auth`, `sync`, `api`, `database`, `mcp`, `ui`

**Data Models**: SwiftData `@Model` classes with `@Attribute(.unique)` for identifiers. Use cascade delete for dependent relationships.

**SwiftData Threading**: Models from `mainContext` must only be accessed on `@MainActor`. SwiftUI's `.task` runs on background threads, so view methods calling repository must be marked `@MainActor`. For repositories, split methods: use `@MainActor` for UI (with in-memory filtering), non-isolated for background sync.

**Async/Await**: Use structured concurrency throughout. Avoid callbacks.

**Testing**: Use `TestFixtures` for consistent test data. Mock protocols for dependency injection.

## Configuration

- OAuth credentials and environment settings in xcconfig files (`Development.xcconfig`, `Production.xcconfig`)
- Never hardcode credentials; load from `AppConfiguration`
- Info.plist contains OAuth URL scheme `cluademail://`

## Task Specifications

Detailed implementation specs are in `.tasks/` directory. 

Read the relevant task file before implementing a feature.

# Task 01: Project Setup & Architecture

## Task Overview

Initialize the Xcode project with proper folder structure, configure dependencies, and establish the foundational app lifecycle. This task sets up the scaffolding that all subsequent tasks will build upon, including error handling infrastructure, logging, testing framework, and configuration management.

## Dependencies

- None (this is the foundation task)

## Architectural Guidelines

### Design Patterns
- **MVVM Architecture**: Use ViewModels to separate business logic from SwiftUI views
- **Repository Pattern**: Abstract data access behind repository protocols
- **Dependency Injection**: Use environment objects and protocol-based DI for testability
- **Actor-based Concurrency**: Use Swift actors for thread-safe state management
- **Result Type Pattern**: Use typed errors with Result for recoverable operations

### SwiftUI/Swift Conventions
- Use `@Observable` macro (iOS 17+/macOS 14+) for observable objects
- Prefer value types (structs) over reference types where appropriate
- Use Swift's structured concurrency (`async/await`, `Task`, `TaskGroup`)
- Follow Swift API Design Guidelines for naming

### File Organization
```
Cluademail/
├── App/
│   ├── CluademailApp.swift
│   ├── AppDelegate.swift
│   └── AppConfiguration.swift
├── Core/
│   ├── Models/
│   ├── Services/
│   ├── Repositories/
│   ├── Utilities/
│   ├── Errors/
│   │   ├── AppError.swift
│   │   ├── ErrorHandler.swift
│   │   └── ErrorAlertModifier.swift
│   └── Logging/
│       └── Logger+Extensions.swift
├── Features/
│   ├── Accounts/
│   ├── EmailList/
│   ├── EmailDetail/
│   ├── Compose/
│   ├── Search/
│   └── Settings/
├── MCP/
│   ├── Server/
│   └── Tools/
├── Resources/
│   ├── Assets.xcassets
│   └── Configuration/
│       ├── Development.xcconfig
│       ├── Staging.xcconfig
│       └── Production.xcconfig
└── Supporting/
    ├── Info.plist
    └── Cluademail.entitlements

CluademailTests/
├── Unit/
│   ├── Services/
│   ├── Repositories/
│   └── ViewModels/
├── Integration/
│   └── APIIntegrationTests.swift
├── Mocks/
│   ├── MockEmailRepository.swift
│   ├── MockGmailService.swift
│   └── MockAccountRepository.swift
└── TestHelpers/
    ├── TestFixtures.swift
    └── XCTestCase+Extensions.swift

CluademailUITests/
├── EmailListUITests.swift
├── ComposeUITests.swift
└── SettingsUITests.swift
```

## Implementation Details

### Components to Create

1. **Xcode Project**
   - Create new macOS App project named "Cluademail"
   - Target: macOS 14.0+ (Sonoma)
   - Interface: SwiftUI
   - Language: Swift
   - Storage: SwiftData
   - Include Unit Tests: Yes
   - Include UI Tests: Yes

2. **App Entry Point** (`CluademailApp.swift`)
   - Main app structure with WindowGroup
   - Inject AppState and ErrorHandler into environment
   - Configure ModelContainer for SwiftData models
   - Add Settings scene for preferences window
   - Configure menu bar commands (New Message, Check Mail)

3. **App Delegate** (`AppDelegate.swift`)
   - Handle app lifecycle events
   - Log application launch/terminate
   - Setup notifications on launch
   - Start/stop MCP server based on settings
   - Return false for `applicationShouldTerminateAfterLastWindowClosed` (keep running)

4. **App Configuration** (`AppConfiguration.swift`)
   - Define logging subsystem: `com.cluademail.app`
   - Enum for environments: development, staging, production
   - Load `GOOGLE_CLIENT_ID` from Info.plist (fatal if missing)
   - Define OAuth redirect URI: `cluademail://oauth/callback`
   - Toggle verbose logging based on environment

5. **Entitlements & Capabilities**
   - App Sandbox: enabled
   - Network (Outgoing connections): enabled for Gmail API
   - Keychain Access: for secure token storage
   - User Selected File (Read/Write): for attachments

6. **Info.plist Configuration**
   - URL scheme for OAuth callback: `cluademail://`
   - LSUIElement: NO (show in dock)
   - Bundle identifiers and versioning

### Error Handling Infrastructure

**AppError Protocol**:
- Properties: `errorCode` (String), `isRecoverable` (Bool), `underlyingError` (Error?)
- Conforms to: `LocalizedError`, `Sendable`

**Domain Error Types**:

| Type | Cases | Recovery |
|------|-------|----------|
| AuthError | userCancelled, invalidCredentials, tokenExpired, tokenRefreshFailed, keychainError, networkError | userCancelled/networkError recoverable |
| SyncError | networkUnavailable, historyExpired, quotaExceeded, syncInProgress, partialFailure, databaseError | All recoverable |
| APIError | unauthorized, notFound, rateLimited, invalidResponse, serverError, networkError, decodingError | rateLimited/networkError/serverError recoverable |

**ErrorHandler Service** (`@Observable`):
- Properties: `currentError`, `showingError` (Bool)
- Methods: `handle(error:context:)` - logs and optionally shows alert
- Method: `showError(_:)` - displays error to user (MainActor)
- Method: `dismissError()` - clears current error

**ErrorAlertModifier**:
- ViewModifier that attaches alert to root view
- Shows OK button always, Retry button if recoverable

### Logging Infrastructure

**Logger Extension Categories**:
- `Logger.auth` - authentication operations
- `Logger.sync` - sync operations
- `Logger.api` - API calls
- `Logger.database` - database operations
- `Logger.mcp` - MCP server
- `Logger.ui` - UI events

**Privacy-Aware Logging**:
- Helper method: `logSensitive(message:sensitiveValue:)` - logs with `.private` privacy

### App State

**AppState** (`@Observable`):
- `selectedAccount`: Account?
- `selectedFolder`: Folder = .inbox
- `selectedEmail`: Email?
- `isSyncing`: Bool
- `mcpServerRunning`: Bool
- `lastError`: AppError?

**Folder Enum**:
- Cases: inbox, sent, drafts, trash, spam, starred, allMail
- Raw values map to Gmail label IDs (INBOX, SENT, DRAFT, etc.)
- Computed: `displayName`, `systemImage` (SF Symbol)

### Build Configurations

Create xcconfig files for each environment:

**Development.xcconfig**:
```
GOOGLE_CLIENT_ID = your-dev-client-id.apps.googleusercontent.com
APP_ENVIRONMENT = development
```

**Production.xcconfig**:
```
GOOGLE_CLIENT_ID = $(GOOGLE_CLIENT_ID_PROD)
APP_ENVIRONMENT = production
```

Note: Add xcconfig files to .gitignore to protect credentials.

### Testing Infrastructure

**Mock Protocol Implementations**:
- Create mocks for all repository protocols
- Track method calls (fetchCalled, saveCalled, etc.)
- Allow injecting errors for testing error paths

**Test Fixtures**:
- Factory methods: `makeAccount()`, `makeEmail()`
- Accept optional parameters for customization

**XCTestCase Extensions**:
- `XCTAssertThrowsErrorAsync` - test async throwing functions
- `waitForAsync(timeout:operation:)` - helper for async tests

### CI/CD Considerations

GitHub Actions workflow structure (`.github/workflows/ci.yml`):
- Runs on: macos-14
- Steps: checkout, select Xcode, build, test
- Use xcodebuild with scheme "Cluademail" and destination "platform=macOS"

## Acceptance Criteria

- [ ] Xcode project created with correct bundle identifier and team settings
- [ ] Folder structure matches the defined architecture
- [ ] App builds and runs on macOS 14+
- [ ] App shows a basic window with placeholder content
- [ ] Entitlements file configured with required capabilities
- [ ] Info.plist contains OAuth URL scheme
- [ ] AppState observable is created and injected into environment
- [ ] Basic menu bar with Preferences item opens Settings window
- [ ] Project compiles with no warnings
- [ ] **Error handling infrastructure in place**
  - [ ] `AppError` protocol defined with domain-specific implementations
  - [ ] `ErrorHandler` service created and injected via environment
  - [ ] `ErrorAlertModifier` attached to root view
- [ ] **Logging infrastructure in place**
  - [ ] `Logger` extensions with category-based loggers
  - [ ] Privacy-aware logging helpers available
- [ ] **Configuration management**
  - [ ] xcconfig files created for each environment
  - [ ] `AppConfiguration` loads values from Info.plist
  - [ ] Sensitive values (GOOGLE_CLIENT_ID) not hardcoded
- [ ] **Testing infrastructure**
  - [ ] Unit test target created with example test
  - [ ] UI test target created
  - [ ] Mock implementations for core protocols
  - [ ] Test fixtures and helpers available
- [ ] **CI/CD ready**
  - [ ] Project builds from command line with xcodebuild
  - [ ] Tests run from command line

## References

- [SwiftUI App Structure](https://developer.apple.com/documentation/swiftui/app)
- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [macOS Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements)
- [Swift Package Manager](https://developer.apple.com/documentation/xcode/swift-packages)
- [Unified Logging](https://developer.apple.com/documentation/os/logging)
- [Error Handling in Swift](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/errorhandling/)
- [XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [Xcode Build Settings](https://developer.apple.com/documentation/xcode/build-settings-reference)

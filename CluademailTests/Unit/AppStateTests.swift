import XCTest
@testable import Cluademail

@MainActor
final class AppStateTests: XCTestCase {

    var sut: AppState!

    override func setUp() async throws {
        sut = AppState()
    }

    override func tearDown() async throws {
        sut = nil
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertNil(sut.selectedAccount)
        XCTAssertEqual(sut.selectedFolder, .inbox)
        XCTAssertNil(sut.selectedEmail)
        XCTAssertFalse(sut.isSyncing)
        XCTAssertFalse(sut.mcpServerRunning)
        XCTAssertNil(sut.lastSyncDate)
    }

    // MARK: - Selection Tests

    func testFolderSelection() {
        sut.selectedFolder = .sent
        XCTAssertEqual(sut.selectedFolder, .sent)

        sut.selectedFolder = .drafts
        XCTAssertEqual(sut.selectedFolder, .drafts)
    }

    func testAccountSelection() {
        let account = Account(email: "test@gmail.com", displayName: "Test")

        sut.selectedAccount = account
        XCTAssertEqual(sut.selectedAccount?.email, "test@gmail.com")

        sut.selectedAccount = nil
        XCTAssertNil(sut.selectedAccount)
    }

    // MARK: - State Updates

    func testSyncStateUpdate() {
        sut.isSyncing = true
        XCTAssertTrue(sut.isSyncing)

        sut.lastSyncDate = Date()
        XCTAssertNotNil(sut.lastSyncDate)

        sut.isSyncing = false
        XCTAssertFalse(sut.isSyncing)
    }

    func testMCPStateUpdate() {
        sut.mcpServerRunning = true
        XCTAssertTrue(sut.mcpServerRunning)

        sut.mcpServerRunning = false
        XCTAssertFalse(sut.mcpServerRunning)
    }
}

// MARK: - Folder Tests

final class FolderTests: XCTestCase {

    func testFolderRawValues() {
        XCTAssertEqual(Folder.inbox.rawValue, "INBOX")
        XCTAssertEqual(Folder.sent.rawValue, "SENT")
        XCTAssertEqual(Folder.drafts.rawValue, "DRAFT")
        XCTAssertEqual(Folder.trash.rawValue, "TRASH")
        XCTAssertEqual(Folder.spam.rawValue, "SPAM")
        XCTAssertEqual(Folder.starred.rawValue, "STARRED")
        XCTAssertEqual(Folder.allMail.rawValue, "ALL_MAIL")
    }

    func testFolderDisplayNames() {
        XCTAssertEqual(Folder.inbox.displayName, "Inbox")
        XCTAssertEqual(Folder.sent.displayName, "Sent")
        XCTAssertEqual(Folder.drafts.displayName, "Drafts")
        XCTAssertEqual(Folder.trash.displayName, "Trash")
        XCTAssertEqual(Folder.spam.displayName, "Spam")
        XCTAssertEqual(Folder.starred.displayName, "Starred")
        XCTAssertEqual(Folder.allMail.displayName, "All Mail")
    }

    func testFolderSystemImages() {
        XCTAssertEqual(Folder.inbox.systemImage, "tray")
        XCTAssertEqual(Folder.sent.systemImage, "paperplane")
        XCTAssertEqual(Folder.drafts.systemImage, "doc")
        XCTAssertEqual(Folder.trash.systemImage, "trash")
        XCTAssertEqual(Folder.spam.systemImage, "exclamationmark.triangle")
        XCTAssertEqual(Folder.starred.systemImage, "star")
        XCTAssertEqual(Folder.allMail.systemImage, "tray.full")
    }

    func testFolderIdentifiable() {
        XCTAssertEqual(Folder.inbox.id, "INBOX")
        XCTAssertEqual(Folder.sent.id, "SENT")
    }

    func testAllCases() {
        XCTAssertEqual(Folder.allCases.count, 7)
    }
}

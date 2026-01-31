import XCTest
@testable import Cluademail

/// Tests for Gmail DTO JSON encoding/decoding.
final class GmailDTOsTests: XCTestCase {

    // MARK: - GmailMessageDTO Tests

    func testGmailMessageDTODecoding() throws {
        let json = """
        {
            "id": "msg123",
            "threadId": "thread456",
            "labelIds": ["INBOX", "UNREAD"],
            "snippet": "This is a test email...",
            "internalDate": "1704067200000"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(GmailMessageDTO.self, from: data)

        XCTAssertEqual(message.id, "msg123")
        XCTAssertEqual(message.threadId, "thread456")
        XCTAssertEqual(message.labelIds, ["INBOX", "UNREAD"])
        XCTAssertEqual(message.snippet, "This is a test email...")
        XCTAssertEqual(message.internalDate, "1704067200000")
        XCTAssertNil(message.payload)
    }

    func testGmailMessageDTOWithPayload() throws {
        let json = """
        {
            "id": "msg123",
            "threadId": "thread456",
            "payload": {
                "mimeType": "text/plain",
                "headers": [
                    {"name": "From", "value": "sender@gmail.com"},
                    {"name": "Subject", "value": "Test Subject"}
                ],
                "body": {
                    "size": 100,
                    "data": "SGVsbG8gV29ybGQ="
                }
            }
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(GmailMessageDTO.self, from: data)

        XCTAssertNotNil(message.payload)
        XCTAssertEqual(message.payload?.mimeType, "text/plain")
        XCTAssertEqual(message.payload?.headers?.count, 2)
        XCTAssertEqual(message.payload?.body?.size, 100)
        XCTAssertEqual(message.payload?.body?.data, "SGVsbG8gV29ybGQ=")
    }

    // MARK: - HeaderDTO Tests

    func testHeaderDTODecoding() throws {
        let json = """
        {"name": "Subject", "value": "Test Email Subject"}
        """

        let data = json.data(using: .utf8)!
        let header = try JSONDecoder().decode(HeaderDTO.self, from: data)

        XCTAssertEqual(header.name, "Subject")
        XCTAssertEqual(header.value, "Test Email Subject")
    }

    // MARK: - BodyDTO Tests

    func testBodyDTODecoding() throws {
        let json = """
        {
            "size": 1024,
            "data": "base64encodeddata",
            "attachmentId": "att123"
        }
        """

        let data = json.data(using: .utf8)!
        let body = try JSONDecoder().decode(BodyDTO.self, from: data)

        XCTAssertEqual(body.size, 1024)
        XCTAssertEqual(body.data, "base64encodeddata")
        XCTAssertEqual(body.attachmentId, "att123")
    }

    func testBodyDTOWithOptionalFields() throws {
        let json = """
        {"size": 0}
        """

        let data = json.data(using: .utf8)!
        let body = try JSONDecoder().decode(BodyDTO.self, from: data)

        XCTAssertEqual(body.size, 0)
        XCTAssertNil(body.data)
        XCTAssertNil(body.attachmentId)
    }

    // MARK: - PartDTO Tests

    func testPartDTOWithNestedParts() throws {
        let json = """
        {
            "partId": "0",
            "mimeType": "multipart/alternative",
            "parts": [
                {
                    "partId": "0.0",
                    "mimeType": "text/plain",
                    "body": {"size": 50}
                },
                {
                    "partId": "0.1",
                    "mimeType": "text/html",
                    "body": {"size": 100}
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let part = try JSONDecoder().decode(PartDTO.self, from: data)

        XCTAssertEqual(part.partId, "0")
        XCTAssertEqual(part.mimeType, "multipart/alternative")
        XCTAssertEqual(part.parts?.count, 2)
        XCTAssertEqual(part.parts?[0].mimeType, "text/plain")
        XCTAssertEqual(part.parts?[1].mimeType, "text/html")
    }

    // MARK: - GmailMessageListDTO Tests

    func testGmailMessageListDTODecoding() throws {
        let json = """
        {
            "messages": [
                {"id": "msg1", "threadId": "thread1"},
                {"id": "msg2", "threadId": "thread2"}
            ],
            "nextPageToken": "token123",
            "resultSizeEstimate": 100
        }
        """

        let data = json.data(using: .utf8)!
        let list = try JSONDecoder().decode(GmailMessageListDTO.self, from: data)

        XCTAssertEqual(list.messages?.count, 2)
        XCTAssertEqual(list.nextPageToken, "token123")
        XCTAssertEqual(list.resultSizeEstimate, 100)
    }

    // MARK: - GmailLabelDTO Tests

    func testGmailLabelDTODecoding() throws {
        let json = """
        {
            "id": "INBOX",
            "name": "Inbox",
            "type": "system",
            "messageListVisibility": "show",
            "labelListVisibility": "labelShow",
            "messagesTotal": 1000,
            "messagesUnread": 50
        }
        """

        let data = json.data(using: .utf8)!
        let label = try JSONDecoder().decode(GmailLabelDTO.self, from: data)

        XCTAssertEqual(label.id, "INBOX")
        XCTAssertEqual(label.name, "Inbox")
        XCTAssertEqual(label.type, "system")
        XCTAssertEqual(label.messagesTotal, 1000)
        XCTAssertEqual(label.messagesUnread, 50)
    }

    func testGmailLabelDTOWithColor() throws {
        let json = """
        {
            "id": "Label_1",
            "name": "Work",
            "type": "user",
            "color": {
                "textColor": "#000000",
                "backgroundColor": "#16a765"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let label = try JSONDecoder().decode(GmailLabelDTO.self, from: data)

        XCTAssertEqual(label.id, "Label_1")
        XCTAssertEqual(label.color?.textColor, "#000000")
        XCTAssertEqual(label.color?.backgroundColor, "#16a765")
    }

    // MARK: - GmailHistoryDTO Tests

    func testGmailHistoryListDTODecoding() throws {
        let json = """
        {
            "history": [
                {
                    "id": "12345",
                    "messagesAdded": [
                        {"message": {"id": "msg1", "threadId": "thread1"}}
                    ]
                }
            ],
            "historyId": "12346"
        }
        """

        let data = json.data(using: .utf8)!
        let historyList = try JSONDecoder().decode(GmailHistoryListDTO.self, from: data)

        XCTAssertEqual(historyList.history?.count, 1)
        XCTAssertEqual(historyList.historyId, "12346")
        XCTAssertEqual(historyList.history?[0].messagesAdded?.count, 1)
    }

    // MARK: - Test Fixtures Tests

    func testMakeGmailMessageDTOFixture() {
        let dto = TestFixtures.makeGmailMessageDTO(
            id: "test-id",
            threadId: "test-thread"
        )

        XCTAssertEqual(dto.id, "test-id")
        XCTAssertEqual(dto.threadId, "test-thread")
        XCTAssertNotNil(dto.payload)
    }

    func testMakePayloadDTOFixture() {
        let payload = TestFixtures.makePayloadDTO()

        XCTAssertNotNil(payload.headers)
        XCTAssertEqual(payload.mimeType, "text/plain")
    }

    func testMakeGmailLabelDTOFixture() {
        let dto = TestFixtures.makeGmailLabelDTO(
            id: "SENT",
            name: "Sent Mail"
        )

        XCTAssertEqual(dto.id, "SENT")
        XCTAssertEqual(dto.name, "Sent Mail")
    }
}

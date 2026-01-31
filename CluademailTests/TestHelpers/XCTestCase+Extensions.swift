import XCTest

extension XCTestCase {

    /// Asserts that an async throwing function throws an error of the expected type.
    /// - Parameters:
    ///   - expression: The async throwing expression to evaluate
    ///   - errorType: The expected error type
    ///   - message: Optional failure message
    ///   - file: The file where the assertion occurs
    ///   - line: The line where the assertion occurs
    ///   - errorHandler: Optional handler to further inspect the thrown error
    func XCTAssertThrowsErrorAsync<T, E: Error>(
        _ expression: @autoclosure () async throws -> T,
        ofType errorType: E.Type,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        errorHandler: ((E) -> Void)? = nil
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error of type \(errorType) but no error was thrown. \(message)", file: file, line: line)
        } catch let error as E {
            errorHandler?(error)
        } catch {
            XCTFail("Expected error of type \(errorType) but got \(type(of: error)): \(error). \(message)", file: file, line: line)
        }
    }

    /// Waits for an async operation to complete with a timeout.
    /// - Parameters:
    ///   - timeout: Maximum time to wait in seconds
    ///   - operation: The async operation to perform
    /// - Returns: The result of the operation
    func waitForAsync<T>(
        timeout: TimeInterval = 5.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TimeoutError()
            }

            guard let result = try await group.next() else {
                throw TimeoutError()
            }

            group.cancelAll()
            return result
        }
    }

    /// Error thrown when an async operation times out.
    struct TimeoutError: Error {}
}

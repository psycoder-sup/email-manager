import Foundation
import os.log

/// Actor for reading and writing JSON-RPC messages over stdio with Content-Length framing.
actor StdioTransport {

    private let stdin: FileHandle
    private let stdout: FileHandle
    private var isClosed = false
    private var buffer = Data()

    /// Maximum buffer size to prevent DoS via unbounded memory growth (10MB)
    private let maxBufferSize = 10 * 1024 * 1024

    init() {
        self.stdin = FileHandle.standardInput
        self.stdout = FileHandle.standardOutput
    }

    /// Creates a StdioTransport with custom file handles (for testing).
    init(stdin: FileHandle, stdout: FileHandle) {
        self.stdin = stdin
        self.stdout = stdout
    }

    // MARK: - Read

    /// Reads one message from stdin (newline-delimited JSON per MCP spec).
    /// - Returns: Message data, or nil on EOF
    /// - Throws: On read or parse errors
    func readMessage() async throws -> Data? {
        guard !isClosed else { return nil }

        // MCP stdio uses newline-delimited JSON (NDJSON)
        // Each message is a single line of JSON, terminated by newline
        guard let line = try await readLine() else {
            return nil // EOF
        }

        // Skip empty lines
        guard !line.isEmpty else {
            return try await readMessage()
        }

        guard let data = line.data(using: .utf8) else {
            throw MCPError.parseError("Invalid UTF-8 in message")
        }

        Logger.mcp.debug("Received message: \(data.count) bytes")
        return data
    }

    // MARK: - Write

    /// Writes a message to stdout (newline-delimited JSON per MCP spec).
    /// - Parameter data: The message data to write
    func writeMessage(_ data: Data) throws {
        guard !isClosed else { return }

        // MCP stdio uses newline-delimited JSON
        // Write message followed by newline
        var output = Data()
        output.append(data)
        output.append(Data("\n".utf8))

        stdout.write(output)

        Logger.mcp.debug("Sent message: \(data.count) bytes")
    }

    /// Writes a JSON-RPC response.
    func writeResponse(_ response: JSONRPCResponse) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        try writeMessage(data)
    }

    /// Writes a JSON-RPC error response.
    func writeError(_ error: JSONRPCErrorResponse) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(error)
        try writeMessage(data)
    }

    // MARK: - Close

    /// Closes the transport.
    func close() {
        isClosed = true
    }

    // MARK: - Private

    /// Reads a line from stdin (terminated by \r\n or \n).
    private func readLine() async throws -> String? {
        while true {
            // Check for CRLF first, then LF (support both line ending styles)
            if let crlfRange = buffer.range(of: Data("\r\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<crlfRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<crlfRange.upperBound)
                return String(data: lineData, encoding: .utf8)
            } else if let lfRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<lfRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<lfRange.upperBound)
                return String(data: lineData, encoding: .utf8)
            }

            // Read more data - wrap blocking call to yield to async runtime
            let chunk = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [stdin] in
                    let data = stdin.availableData
                    continuation.resume(returning: data)
                }
            }

            if chunk.isEmpty {
                // EOF
                if buffer.isEmpty {
                    return nil
                }
                // Return remaining buffer as final line
                let remaining = String(data: buffer, encoding: .utf8)
                buffer.removeAll()
                return remaining
            }

            buffer.append(chunk)

            // Check buffer size to prevent unbounded growth
            if buffer.count > maxBufferSize {
                throw MCPError.parseError("Message too large (exceeds 10MB limit)")
            }
        }
    }

}

import Foundation
import Network

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let query: [String: String]
    public let headers: [String: String]
    public let body: Data
}

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let reasonPhrase: String
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, reasonPhrase: String, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase
        self.headers = headers
        self.body = body
    }

    public static func json(statusCode: Int = 200, body: Data) -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            reasonPhrase: HTTPResponse.reasonPhrase(for: statusCode),
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: body
        )
    }

    public static func text(statusCode: Int = 200, body: String, contentType: String = "text/plain; charset=utf-8") -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            reasonPhrase: HTTPResponse.reasonPhrase(for: statusCode),
            headers: ["Content-Type": contentType],
            body: Data(body.utf8)
        )
    }

    public static func empty(statusCode: Int = 204) -> HTTPResponse {
        HTTPResponse(statusCode: statusCode, reasonPhrase: HTTPResponse.reasonPhrase(for: statusCode))
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 422: return "Unprocessable Entity"
        case 500: return "Internal Server Error"
        default: return "HTTP Status"
        }
    }
}

final class HTTPRequestParser {
    func parse(_ data: Data) -> HTTPRequest? {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }
        let headerData = data[..<boundary.lowerBound]
        let bodyStartIndex = boundary.upperBound
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }

        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else {
            return nil
        }

        let method = String(requestParts[0])
        let rawPath = String(requestParts[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        guard data.count >= bodyStartIndex + contentLength else {
            return nil
        }

        let body = Data(data[bodyStartIndex..<bodyStartIndex + contentLength])
        let components = URLComponents(string: rawPath)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let path = components?.path ?? rawPath
        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: body)
    }
}

private final class ListenerStartState: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed {
            return false
        }
        resumed = true
        return true
    }
}

public final class LocalHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "swiftlm.http.server", qos: .userInitiated)
    private let parser = HTTPRequestParser()
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse

    public init(port: UInt16, handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "SwiftLM.LocalHTTPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
        }
        self.listener = try NWListener(using: .tcp, on: nwPort)
        self.handler = handler
    }

    public func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let startState = ListenerStartState()
            listener.stateUpdateHandler = { listenerState in
                switch listenerState {
                case .ready:
                    if startState.claim() {
                        continuation.resume()
                    }
                case let .failed(error):
                    if startState.claim() {
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.configure(connection: connection)
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        listener.cancel()
    }

    private func configure(connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed = state {
                connection.cancel()
            }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                connection.cancel()
                print("SwiftLM HTTP receive error: \(error)")
                return
            }

            var updatedBuffer = buffer
            if let data {
                updatedBuffer.append(data)
            }

            if let request = self.parser.parse(updatedBuffer) {
                Task {
                    let response = await self.handler(request)
                    self.queue.async {
                        self.send(response, on: connection)
                    }
                }
                return
            }

            if isComplete {
                connection.cancel()
                return
            }

            self.receive(on: connection, buffer: updatedBuffer)
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        var headers = response.headers
        headers["Content-Length"] = "\(response.body.count)"
        headers["Connection"] = "close"
        let headerLines = headers.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
        let headerText = "HTTP/1.1 \(response.statusCode) \(response.reasonPhrase)\r\n\(headerLines)\r\n\r\n"
        var responseData = Data(headerText.utf8)
        responseData.append(response.body)
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

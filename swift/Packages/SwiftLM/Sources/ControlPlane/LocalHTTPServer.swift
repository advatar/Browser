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
        case 413: return "Payload Too Large"
        case 422: return "Unprocessable Entity"
        case 500: return "Internal Server Error"
        default: return "HTTP Status"
        }
    }
}

enum HTTPRequestParseFailure: Equatable {
    case badRequest(String)
    case payloadTooLarge(String)

    var response: HTTPResponse {
        switch self {
        case let .badRequest(message):
            return .text(statusCode: 400, body: message)
        case let .payloadTooLarge(message):
            return .text(statusCode: 413, body: message)
        }
    }
}

enum HTTPRequestParseResult {
    case incomplete
    case request(HTTPRequest)
    case failure(HTTPRequestParseFailure)
}

final class HTTPRequestParser {
    static let defaultMaximumHeaderBytes = 32 * 1_024
    static let defaultMaximumBodyBytes = 8 * 1_024 * 1_024

    private let maximumHeaderBytes: Int
    private let maximumBodyBytes: Int

    init(
        maximumHeaderBytes: Int = HTTPRequestParser.defaultMaximumHeaderBytes,
        maximumBodyBytes: Int = HTTPRequestParser.defaultMaximumBodyBytes
    ) {
        self.maximumHeaderBytes = max(maximumHeaderBytes, 1)
        self.maximumBodyBytes = max(maximumBodyBytes, 0)
    }

    func parse(_ data: Data) -> HTTPRequestParseResult {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maximumHeaderBytes
                ? .failure(.payloadTooLarge("HTTP request headers exceed the configured limit."))
                : .incomplete
        }
        let headerData = data[..<boundary.lowerBound]
        guard headerData.count <= maximumHeaderBytes else {
            return .failure(.payloadTooLarge("HTTP request headers exceed the configured limit."))
        }
        let bodyStartIndex = boundary.upperBound
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return .failure(.badRequest("HTTP request headers must be valid UTF-8."))
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return .failure(.badRequest("HTTP request line is missing."))
        }

        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3, requestParts[2].hasPrefix("HTTP/") else {
            return .failure(.badRequest("HTTP request line is malformed."))
        }

        let method = String(requestParts[0])
        let rawPath = String(requestParts[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard line.isEmpty == false else { continue }
            guard let colon = line.firstIndex(of: ":") else {
                return .failure(.badRequest("HTTP request header is malformed."))
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false else {
                return .failure(.badRequest("HTTP request header name is missing."))
            }
            if key == "content-length", let existing = headers[key], existing != value {
                return .failure(.badRequest("HTTP request has conflicting Content-Length headers."))
            }
            headers[key] = value
        }

        let contentLength: Int
        if let rawContentLength = headers["content-length"] {
            guard let parsedContentLength = Int(rawContentLength), parsedContentLength >= 0 else {
                return .failure(.badRequest("Content-Length must be a non-negative integer."))
            }
            contentLength = parsedContentLength
        } else {
            contentLength = 0
        }
        guard contentLength <= maximumBodyBytes else {
            return .failure(.payloadTooLarge("HTTP request body exceeds the configured limit."))
        }
        guard headers["transfer-encoding"] == nil else {
            return .failure(.badRequest("Transfer-Encoding is not supported by this local server."))
        }
        guard let bodyEndIndex = data.index(
            bodyStartIndex,
            offsetBy: contentLength,
            limitedBy: data.endIndex
        ) else {
            return .incomplete
        }

        let body = Data(data[bodyStartIndex..<bodyEndIndex])
        guard let components = URLComponents(string: rawPath), components.path.isEmpty == false else {
            return .failure(.badRequest("HTTP request target is malformed."))
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        return .request(HTTPRequest(
            method: method,
            path: components.path,
            query: query,
            headers: headers,
            body: body
        ))
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
    static let loopbackHost = NWEndpoint.Host("127.0.0.1")

    private let listener: NWListener
    private let queue = DispatchQueue(label: "swiftlm.http.server", qos: .userInitiated)
    private let parser = HTTPRequestParser()
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse

    public init(port: UInt16, handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "SwiftLM.LocalHTTPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: Self.loopbackHost, port: nwPort)
        self.listener = try NWListener(using: parameters)
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

            switch self.parser.parse(updatedBuffer) {
            case let .request(request):
                Task {
                    let response = await self.handler(request)
                    self.queue.async {
                        self.send(response, on: connection)
                    }
                }
                return
            case let .failure(failure):
                self.send(failure.response, on: connection)
                return
            case .incomplete:
                break
            }

            if isComplete {
                self.send(
                    HTTPRequestParseFailure.badRequest("HTTP request ended before it was complete.").response,
                    on: connection
                )
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

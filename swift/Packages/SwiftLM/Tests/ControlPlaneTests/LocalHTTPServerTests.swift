import Foundation
import Testing
@testable import ControlPlane

@Test
func httpRequestParserAcceptsCompleteBoundedRequest() throws {
    let parser = HTTPRequestParser(maximumHeaderBytes: 1_024, maximumBodyBytes: 64)
    let payload = Data(
        "POST /app/v1/models/import?q=swift HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r\ntest".utf8
    )

    let request = try #require(parsedRequest(from: parser.parse(payload)))

    #expect(request.method == "POST")
    #expect(request.path == "/app/v1/models/import")
    #expect(request.query == ["q": "swift"])
    #expect(request.body == Data("test".utf8))
}

@Test
func httpRequestParserKeepsFirstDuplicateQueryValue() throws {
    let parser = HTTPRequestParser()
    let payload = Data("GET /app/v1/models/search?q=first&q=second&limit=4 HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)

    let request = try #require(parsedRequest(from: parser.parse(payload)))

    #expect(request.query["q"] == "first")
    #expect(request.query["limit"] == "4")
}

@Test(arguments: [
    "Content-Length: -1",
    "Content-Length: not-a-number",
    "Content-Length: 999999999999999999999999999999999999999"
])
func httpRequestParserRejectsInvalidContentLength(header: String) {
    let parser = HTTPRequestParser()
    let payload = Data("POST /app/v1/models/import HTTP/1.1\r\n\(header)\r\n\r\n".utf8)

    let failure = parsedFailure(from: parser.parse(payload))

    #expect(failure?.response.statusCode == 400)
}

@Test
func httpRequestParserRejectsOversizedHeadersAndBodies() {
    let parser = HTTPRequestParser(maximumHeaderBytes: 32, maximumBodyBytes: 4)
    let oversizedHeader = Data("GET / HTTP/1.1\r\nX-Long: \(String(repeating: "x", count: 64))".utf8)
    let oversizedBody = Data("POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\n".utf8)

    let headerFailure = parsedFailure(from: parser.parse(oversizedHeader))
    let bodyFailure = parsedFailure(from: parser.parse(oversizedBody))

    #expect(headerFailure?.response.statusCode == 413)
    #expect(bodyFailure?.response.statusCode == 413)
    #expect(headerFailure?.response.reasonPhrase == "Payload Too Large")
}

@Test
func httpRequestParserWaitsForDeclaredBody() {
    let parser = HTTPRequestParser(maximumBodyBytes: 64)
    let payload = Data("POST / HTTP/1.1\r\nContent-Length: 4\r\n\r\nab".utf8)

    switch parser.parse(payload) {
    case .incomplete:
        break
    case .request, .failure:
        Issue.record("Expected the parser to wait for the remaining declared body bytes.")
    }
}

private func parsedRequest(from result: HTTPRequestParseResult) -> HTTPRequest? {
    guard case let .request(request) = result else {
        return nil
    }
    return request
}

private func parsedFailure(from result: HTTPRequestParseResult) -> HTTPRequestParseFailure? {
    guard case let .failure(failure) = result else {
        return nil
    }
    return failure
}

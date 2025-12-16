import XCTest
@testable import AttestationKit

final class AttestationKitTests: XCTestCase {
    func testIssuesToken() throws {
        let payload = Data("payload".utf8)
        let token = try AttestationSigner.shared.issue(subject: "browser.tests", payload: payload)
        XCTAssertEqual(token.subject, "browser.tests")
    }
}

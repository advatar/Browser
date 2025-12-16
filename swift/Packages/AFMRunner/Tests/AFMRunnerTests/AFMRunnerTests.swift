import XCTest
@testable import AFMRunner

final class AFMRunnerTests: XCTestCase {
    func testStubRunnerResponds() throws {
        let request = AFMRunRequest(modelIdentifier: "test", prompt: "ping")
        let response = try AFMRunner.shared.runModel(request)
        XCTAssertTrue(response.output.contains("ping"))
    }
}

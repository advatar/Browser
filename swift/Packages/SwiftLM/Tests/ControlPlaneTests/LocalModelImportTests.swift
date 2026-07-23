import Contracts
import Foundation
import Testing
@testable import ControlPlane

@Test
func localModelImportRejectsMissingPath() {
    let missing = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "missing-swiftlm-model-\(UUID().uuidString)")

    #expect(throws: APIErrorEnvelope.self) {
        try ControlPlaneService.validateLocalModelSource(missing.path)
    }
}

@Test
func localModelImportRejectsRegularFileAndAcceptsReadableDirectory() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "swiftlm-local-model-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "config.json")
    try Data("{}".utf8).write(to: file)

    #expect(throws: APIErrorEnvelope.self) {
        try ControlPlaneService.validateLocalModelSource(file.path)
    }
    try ControlPlaneService.validateLocalModelSource(root.path)
}

import Foundation
import UniversalInteractionKit

/// The Hyperactive Web retention store for dBrowser. Retention is durable on
/// disk today (every service card, capability link, surface, approval, receipt,
/// invocation, and workflow trace is retained with provenance). Mirroring these
/// artifacts into the personal node's governed memory via `OpenMindMemoryClient`
/// (writeback) is the next step of slice 4 (#149).
actor DBrowserArtifactStore: ArtifactStore {
    private let file: FileArtifactStore

    init(rootDirectory: URL) throws {
        self.file = try FileArtifactStore(rootDirectory: rootDirectory)
    }

    func save(_ artifact: ArtifactRecord) async throws {
        try await file.save(artifact)
        // TODO(#149): mirror to OpenMind — openMind.writeback(OpenMindWritebackRequest(...)).
    }

    func load(_ id: ArtifactID) async throws -> ArtifactRecord? {
        try await file.load(id)
    }

    func list(kind: ArtifactKind?) async throws -> [ArtifactRecord] {
        try await file.list(kind: kind)
    }

    func append(_ event: ArtifactEvent) async throws {
        try await file.append(event)
    }
}

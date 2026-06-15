import Foundation
import UniversalInteractionKit

/// The Hyperactive Web retention store for dBrowser. Retention is durable on
/// disk (every service card, capability link, surface, approval, receipt,
/// invocation, and workflow trace is retained with provenance), and each
/// artifact is mirrored into the personal node's governed memory via
/// `OpenMindMemoryClient.writeback` (a no-op until an OpenMind endpoint is
/// configured). Slice 4 of #149.
///
/// `@MainActor` because `OpenMindMemoryClient` is a non-Sendable class used from
/// the main actor elsewhere in the app; the durable file layer is an internal
/// actor, so saves still happen off the main thread.
@MainActor
final class DBrowserArtifactStore: ArtifactStore {
    private let file: FileArtifactStore
    private let openMind: OpenMindMemoryClient

    init(rootDirectory: URL, openMind: OpenMindMemoryClient) throws {
        self.file = try FileArtifactStore(rootDirectory: rootDirectory)
        self.openMind = openMind
    }

    func save(_ artifact: ArtifactRecord) async throws {
        try await file.save(artifact)
        await mirror(artifact)
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

    /// Mirror an artifact into OpenMind as a governed memory (best-effort).
    private func mirror(_ artifact: ArtifactRecord) async {
        let request = OpenMindWritebackRequest(
            runID: UUID(),
            prompt: "",
            pageURLString: artifact.metadata["serviceURI"]?.stringValue,
            summary: "Hyperactive Web \(artifact.kind.rawValue) · \(artifact.digest)",
            source: "dbrowser.hyperactiveweb",
            snapshotCommitment: artifact.digest,
            idempotencyKey: artifact.id.rawValue
        )
        _ = await openMind.writeback(request)
    }
}

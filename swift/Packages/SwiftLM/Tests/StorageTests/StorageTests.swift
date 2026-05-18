@testable import Storage
import Testing

@Test
func storageFindsBundledMigrationsWithoutSourceFallback() {
    let urls = SQLiteStore.migrationURLs(filePath: "/tmp/does-not-exist/Storage.swift")

    #expect(urls.contains(where: { $0.lastPathComponent == "001_initial.sql" }))
}

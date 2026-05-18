import Contracts
import Foundation
import LoggingKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum StorageError: Error, LocalizedError {
    case openDatabase(String)
    case execute(String)
    case migration(String)
    case prepare(String)
    case step(String)

    public var errorDescription: String? {
        switch self {
        case let .openDatabase(message), let .execute(message), let .migration(message), let .prepare(message), let .step(message):
            return message
        }
    }
}

public struct ApplicationPaths: Sendable {
    public let root: URL
    public let databaseDirectory: URL
    public let databaseFile: URL
    public let logsDirectory: URL
    public let modelsDirectory: URL
    public let runtimesDirectory: URL
    public let pythonDirectory: URL
    public let currentDirectory: URL

    public init(root: URL) {
        self.root = root
        self.databaseDirectory = root.appending(path: "db")
        self.databaseFile = databaseDirectory.appending(path: "app.sqlite")
        self.logsDirectory = root.appending(path: "logs")
        self.modelsDirectory = root.appending(path: "models")
        self.runtimesDirectory = root.appending(path: "runtimes")
        self.pythonDirectory = root.appending(path: "python")
        self.currentDirectory = root.appending(path: "current")
    }

    public static func defaultPaths(appName: String = "SwiftLM") -> ApplicationPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return ApplicationPaths(root: base.appending(path: appName))
    }

    public func createIfNeeded() throws {
        let fileManager = FileManager.default
        try [root, databaseDirectory, logsDirectory, modelsDirectory, runtimesDirectory, pythonDirectory, currentDirectory].forEach {
            try fileManager.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }
}

public final class SQLiteStore: @unchecked Sendable {
    private let db: OpaquePointer

    public init(path: String) throws {
        var handle: OpaquePointer?
        if sqlite3_open(path, &handle) != SQLITE_OK {
            throw StorageError.openDatabase("Failed to open SQLite database at \(path)")
        }
        guard let handle else {
            throw StorageError.openDatabase("SQLite returned a nil handle for \(path)")
        }
        self.db = handle
    }

    deinit {
        sqlite3_close(db)
    }

    public func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errorPointer) != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "Unknown SQLite execution failure"
            sqlite3_free(errorPointer)
            throw StorageError.execute(message)
        }
    }

    public func applyMigrations() throws {
        let urls = Self.migrationURLs().sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard urls.isEmpty == false else {
            throw StorageError.migration("No SQLite migration files found in bundled or source resources")
        }
        for url in urls {
            let sql = try String(contentsOf: url)
            try execute(sql)
        }
    }

    public func stringSetting(for key: String) throws -> String? {
        let sql = "SELECT value_json FROM settings WHERE key = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StorageError.prepare(lastErrorMessage())
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW, let cString = sqlite3_column_text(statement, 0) {
            return String(cString: cString)
        }
        if result == SQLITE_DONE {
            return nil
        }
        throw StorageError.step(lastErrorMessage())
    }

    public func upsertSetting(key: String, valueJSON: String) throws {
        let sql = """
        INSERT INTO settings(key, value_json, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json, updated_at = excluded.updated_at;
        """
        try withStatement(sql) { statement in
            sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, valueJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, Time.nowISO8601(), -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StorageError.step(lastErrorMessage())
            }
        }
    }

    public func decodableSetting<Value: Decodable>(_ type: Value.Type, for key: String) throws -> Value? {
        guard let valueJSON = try stringSetting(for: key) else {
            return nil
        }
        return try JSONDecoder().decode(Value.self, from: Data(valueJSON.utf8))
    }

    public func upsertSetting<Value: Encodable>(key: String, value: Value) throws {
        let data = try JSONEncoder().encode(value)
        let json = String(decoding: data, as: UTF8.self)
        try upsertSetting(key: key, valueJSON: json)
    }

    public func recordHardwareSnapshot(_ snapshot: HardwareSnapshot) throws {
        let sql = """
        INSERT INTO hardware_snapshots(
            collected_at, chip_family, performance_cores, efficiency_cores, gpu_cores,
            total_memory_bytes, os_version, metal_available, notes_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let notesData = try JSONEncoder().encode(snapshot.notes)
        let notesJSON = String(decoding: notesData, as: UTF8.self)
        try withStatement(sql) { statement in
            sqlite3_bind_text(statement, 1, Time.nowISO8601(), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, snapshot.chipFamily, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 3, Int32(snapshot.performanceCores))
            sqlite3_bind_int(statement, 4, Int32(snapshot.efficiencyCores))
            sqlite3_bind_int(statement, 5, Int32(snapshot.gpuCores))
            sqlite3_bind_int64(statement, 6, sqlite3_int64(snapshot.totalMemoryBytes))
            sqlite3_bind_text(statement, 7, snapshot.osVersion, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 8, snapshot.metalAvailable ? 1 : 0)
            sqlite3_bind_text(statement, 9, notesJSON, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StorageError.step(lastErrorMessage())
            }
        }
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer?) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StorageError.prepare(lastErrorMessage())
        }
        defer { sqlite3_finalize(statement) }
        try body(statement)
    }

    private func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(db))
    }

    static func migrationURLs(bundle: Bundle = .module, filePath: String = #filePath) -> [URL] {
        let bundled = [
            bundle.urls(forResourcesWithExtension: "sql", subdirectory: "Migrations") ?? [],
            bundle.urls(forResourcesWithExtension: "sql", subdirectory: nil) ?? []
        ]
        .flatMap { $0 }
        .filter { $0.pathExtension == "sql" }

        if bundled.isEmpty == false {
            return deduplicated(urls: bundled)
        }

        let sourceMigrations = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .appending(path: "Resources/Migrations")
        let sourceURLs = (try? FileManager.default.contentsOfDirectory(
            at: sourceMigrations,
            includingPropertiesForKeys: nil
        )) ?? []
        return deduplicated(urls: sourceURLs.filter { $0.pathExtension == "sql" })
    }

    private static func deduplicated(urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.path).inserted
        }
    }
}

public struct PersistenceBootstrap: Sendable {
    public let paths: ApplicationPaths
    public let database: SQLiteStore

    public init(paths: ApplicationPaths = .defaultPaths()) throws {
        self.paths = paths
        try paths.createIfNeeded()
        let database = try SQLiteStore(path: paths.databaseFile.path)
        try database.execute("PRAGMA foreign_keys = ON;")
        try database.execute("PRAGMA journal_mode = WAL;")
        try database.applyMigrations()
        self.database = database
    }

    public func persistBootstrapMetadata(hardware: HardwareSnapshot, logger: AppLogger) async {
        do {
            try database.recordHardwareSnapshot(hardware)
            try database.upsertSetting(key: "last_boot_time", valueJSON: "\"\(Time.nowISO8601())\"")
            await logger.log(level: "info", category: "storage", message: "Bootstrapped SQLite storage.", metadata: [
                "database": paths.databaseFile.path
            ])
        } catch {
            await logger.log(level: "error", category: "storage", message: "Failed to persist bootstrap metadata.", metadata: [
                "error": error.localizedDescription
            ])
        }
    }
}

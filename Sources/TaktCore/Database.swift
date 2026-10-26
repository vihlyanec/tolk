import Foundation
import CSQLite

public final class Database {
    private var connection: OpaquePointer?
    public let url: URL
    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Ошибка открытия базы"
            if let connection { sqlite3_close(connection) }; connection = nil
            throw TaktError.storage(message)
        }
        sqlite3_busy_timeout(connection, 3000)
        do {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else { throw error() }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_int(statement, 0) <= 1 else {
                throw TaktError.invalid("Эта база создана более новой версией Толка")
            }
            sqlite3_finalize(statement); statement = nil
            try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL); PRAGMA user_version=1;")
        } catch {
            sqlite3_close(connection); connection = nil; throw error
        }
    }
    deinit { if let connection { sqlite3_close(connection) } }
    private func error() -> TaktError {
        .storage(connection.map { String(cString: sqlite3_errmsg($0)) } ?? "База закрыта")
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }
    public func load() throws -> Snapshot {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "SELECT payload FROM state WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return Snapshot() }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw error() }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        return try JSONDecoder().decode(Snapshot.self, from: data).validated()
    }
    public func save(_ snapshot: Snapshot) throws {
        let data = try JSONEncoder().encode(snapshot.validated())
        try execute("BEGIN IMMEDIATE")
        do {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, "INSERT INTO state(id,payload) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", -1, &statement, nil) == SQLITE_OK else { throw error() }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let bound = data.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), transient) }
            guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw error() }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func backup(to destination: URL) throws {
        var target: OpaquePointer?
        guard sqlite3_open(destination.path, &target) == SQLITE_OK else {
            if let target { sqlite3_close(target) }; throw TaktError.storage("Не удалось открыть файл резервной копии")
        }
        defer { sqlite3_close(target) }
        guard let backup = sqlite3_backup_init(target, "main", connection, "main") else { throw TaktError.storage("Не удалось начать резервное копирование") }
        let status = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE, finish == SQLITE_OK else { throw TaktError.storage("Резервное копирование не завершено") }
    }
    public static func export(_ snapshot: Snapshot, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot.validated()).write(to: url, options: .atomic)
    }
    public static func readExport(_ url: URL) throws -> Snapshot {
        try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url)).validated()
    }
}

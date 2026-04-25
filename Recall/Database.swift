import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DBValue {
    case int64(Int64)
    case text(String)
    case null

    var int64Value: Int64? { guard case .int64(let v) = self else { return nil }; return v }
    var stringValue: String? { guard case .text(let v) = self else { return nil }; return v }
}

enum DBParam {
    case int64(Int64)
    case text(String)
    case null
}

final class Database {
    private var handle: OpaquePointer?

    init(path: String) throws {
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            throw DBError.open(path)
        }
        try migrate()
    }

    deinit { sqlite3_close(handle) }

    var lastInsertRowid: Int64 { sqlite3_last_insert_rowid(handle) }

    func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errMsg) == SQLITE_OK else {
            let msg = errMsg.map { String(cString: $0) } ?? "exec error"
            sqlite3_free(errMsg)
            throw DBError.exec(msg)
        }
    }

    func run(_ sql: String, _ params: DBParam...) throws {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DBError.step(errmsg())
        }
    }

    func query(_ sql: String, _ params: DBParam...) throws -> [[String: DBValue]] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)
        var rows: [[String: DBValue]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: DBValue] = [:]
            let n = sqlite3_column_count(stmt)
            for i in 0..<n {
                let col = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    row[col] = .int64(sqlite3_column_int64(stmt, i))
                case SQLITE_TEXT:
                    if let ptr = sqlite3_column_text(stmt, i) {
                        let cchar = UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                        row[col] = .text(String(cString: cchar))
                    } else {
                        row[col] = .null
                    }
                default:
                    row[col] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          type TEXT NOT NULL CHECK(type IN ('text','image')),
          text_content TEXT,
          image_path TEXT,
          content_hash TEXT NOT NULL UNIQUE
        );
        CREATE INDEX IF NOT EXISTS idx_updated ON items(updated_at DESC);
        """)
        // Additive migrations — silently ignored if column already exists
        try? exec("ALTER TABLE items ADD COLUMN source_bundle_id TEXT")
        try? exec("ALTER TABLE items ADD COLUMN is_sensitive INTEGER NOT NULL DEFAULT 0")
        try? exec("ALTER TABLE items ADD COLUMN expires_at INTEGER")
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare(errmsg())
        }
        return stmt
    }

    private func bind(_ stmt: OpaquePointer?, _ params: [DBParam]) {
        for (i, p) in params.enumerated() {
            let n = Int32(i + 1)
            switch p {
            case .int64(let v): sqlite3_bind_int64(stmt, n, v)
            case .text(let v):  sqlite3_bind_text(stmt, n, v, -1, sqliteTransient)
            case .null:         sqlite3_bind_null(stmt, n)
            }
        }
    }

    private func errmsg() -> String {
        guard let h = handle, let p = sqlite3_errmsg(h) else { return "unknown error" }
        return String(cString: p)
    }
}

enum DBError: Error {
    case open(String)
    case exec(String)
    case prepare(String)
    case step(String)
}

import Foundation
import SQLite3

/// A small SQLite wrapper (system library; no dependency).
public final class SQLiteDB: @unchecked Sendable {
    let handle: OpaquePointer
    public let path: String

    public init(path: String, readOnly: Bool) throws {
        var h: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(path, &h, flags | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let h else {
            let msg = h.map { String(cString: sqlite3_errmsg($0)) } ?? "can't open"
            if let h { sqlite3_close(h) }
            throw SearchError("index \(path): \(msg)")
        }
        handle = h
        self.path = path
        sqlite3_busy_timeout(h, 5000)  // a reader waits out the writer's commit (SRCH D-4)
    }
    deinit { sqlite3_close(handle) }

    public func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let m = err.map { String(cString: $0) } ?? "error"
            sqlite3_free(err)
            throw SearchError("sql: \(m)")
        }
    }

    public func prepare(_ sql: String) throws -> Statement {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &s, nil) == SQLITE_OK, let s else {
            throw SearchError("sql: \(String(cString: sqlite3_errmsg(handle))) in \(sql.prefix(80))")
        }
        return Statement(s, db: handle)
    }

    public func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        do { try body(); try exec("COMMIT") } catch { try? exec("ROLLBACK"); throw error }
    }

    public var lastRowID: Int64 { sqlite3_last_insert_rowid(handle) }
}

public final class Statement {
    let s: OpaquePointer
    let db: OpaquePointer
    init(_ s: OpaquePointer, db: OpaquePointer) { self.s = s; self.db = db }
    deinit { sqlite3_finalize(s) }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    @discardableResult
    public func bind(_ values: [Any?]) -> Statement {
        sqlite3_reset(s)
        sqlite3_clear_bindings(s)
        for (i, v) in values.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case nil: sqlite3_bind_null(s, idx)
            case let x as Int: sqlite3_bind_int64(s, idx, Int64(x))
            case let x as Int64: sqlite3_bind_int64(s, idx, x)
            case let x as Double: sqlite3_bind_double(s, idx, x)
            case let x as String: sqlite3_bind_text(s, idx, x, -1, Self.transient)
            case let x as Data: _ = x.withUnsafeBytes { sqlite3_bind_blob(s, idx, $0.baseAddress, Int32(x.count), Self.transient) }
            default: sqlite3_bind_null(s, idx)
            }
        }
        return self
    }

    /// Steps once; true when a row is available.
    public func step() throws -> Bool {
        let rc = sqlite3_step(s)
        if rc == SQLITE_ROW { return true }
        if rc == SQLITE_DONE { return false }
        throw SearchError("sql: \(String(cString: sqlite3_errmsg(db)))")
    }

    public func run(_ values: [Any?] = []) throws { bind(values); while try step() {} }

    public func int(_ col: Int32) -> Int { Int(sqlite3_column_int64(s, col)) }
    public func double(_ col: Int32) -> Double { sqlite3_column_double(s, col) }
    public func string(_ col: Int32) -> String? { sqlite3_column_text(s, col).map { String(cString: $0) } }
    public func blob(_ col: Int32) -> Data {
        guard let p = sqlite3_column_blob(s, col) else { return Data() }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(s, col)))
    }
}

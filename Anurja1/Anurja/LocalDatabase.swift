import Foundation
import SQLite3

enum RecordKind: String, CaseIterable {
    case meals, insulin, checkins, sessions
}

/// On-device SQLite store for everything the person logs. Every record is
/// kept as JSON with a `synced` flag, so the app works offline and the sync
/// service only uploads what changed.
final class LocalDatabase: @unchecked Sendable {
    static let shared = LocalDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.anurja.database")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL? = nil) {
        let file = url ?? Self.defaultURL
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if sqlite3_open(file.path, &db) != SQLITE_OK {
            db = nil
            return
        }
        execute("""
        CREATE TABLE IF NOT EXISTS records (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            date REAL NOT NULL,
            body BLOB NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS records_kind_date ON records(kind, date);
        """)
    }

    deinit {
        sqlite3_close(db)
    }

    func save(meals: [MealLog]) { upsert(meals, kind: .meals, id: { $0.id.uuidString }, date: { $0.date }) }
    func save(insulin: [InsulinLog]) { upsert(insulin, kind: .insulin, id: { $0.id.uuidString }, date: { $0.date }) }
    func save(checkIns: [HabitCheckIn]) { upsert(checkIns, kind: .checkins, id: { $0.id.uuidString }, date: { $0.date }) }
    func save(sessions: [CoachSession]) { upsert(sessions, kind: .sessions, id: { $0.id.uuidString }, date: { $0.date }) }

    func load<T: Decodable>(_ kind: RecordKind, as type: T.Type) -> [T] {
        rows(sql: "SELECT id, body FROM records WHERE kind = ? ORDER BY date DESC", kind: kind)
            .compactMap { try? decoder.decode(T.self, from: $0.body) }
    }

    func unsynced<T: Decodable>(_ kind: RecordKind, as type: T.Type) -> [(id: String, value: T)] {
        rows(sql: "SELECT id, body FROM records WHERE kind = ? AND synced = 0 ORDER BY date", kind: kind)
            .compactMap { row in
                (try? decoder.decode(T.self, from: row.body)).map { (id: row.id, value: $0) }
            }
    }

    func markSynced(ids: [String]) {
        guard !ids.isEmpty else { return }
        queue.sync {
            for id in ids {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "UPDATE records SET synced = 1 WHERE id = ?", -1, &statement, nil) == SQLITE_OK else { continue }
                sqlite3_bind_text(statement, 1, id, -1, Self.transient)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
        }
    }

    func count(_ kind: RecordKind) -> Int {
        queue.sync {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM records WHERE kind = ?", -1, &statement, nil) == SQLITE_OK else { return 0 }
            sqlite3_bind_text(statement, 1, kind.rawValue, -1, Self.transient)
            return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
        }
    }

    func clear() {
        execute("DELETE FROM records;")
    }

    // MARK: - Private

    private func upsert<T: Encodable>(_ items: [T], kind: RecordKind, id: (T) -> String, date: (T) -> Date) {
        guard !items.isEmpty else { return }
        let encoded = items.compactMap { item -> (String, Double, Data)? in
            guard let data = try? encoder.encode(item) else { return nil }
            return (id(item), date(item).timeIntervalSince1970, data)
        }
        queue.sync {
            execute("BEGIN TRANSACTION;", locked: true)
            for (recordID, time, body) in encoded {
                var statement: OpaquePointer?
                let sql = """
                INSERT INTO records (id, kind, date, body, synced) VALUES (?, ?, ?, ?, 0)
                ON CONFLICT(id) DO UPDATE SET
                    date = excluded.date,
                    body = excluded.body,
                    synced = CASE WHEN records.body = excluded.body THEN records.synced ELSE 0 END;
                """
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
                sqlite3_bind_text(statement, 1, recordID, -1, Self.transient)
                sqlite3_bind_text(statement, 2, kind.rawValue, -1, Self.transient)
                sqlite3_bind_double(statement, 3, time)
                _ = body.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, 4, buffer.baseAddress, Int32(buffer.count), Self.transient)
                }
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
            execute("COMMIT;", locked: true)
        }
    }

    private func rows(sql: String, kind: RecordKind) -> [(id: String, body: Data)] {
        queue.sync {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_text(statement, 1, kind.rawValue, -1, Self.transient)
            var result: [(id: String, body: Data)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idText = sqlite3_column_text(statement, 0) else { continue }
                let length = Int(sqlite3_column_bytes(statement, 1))
                guard let bytes = sqlite3_column_blob(statement, 1), length > 0 else { continue }
                result.append((id: String(cString: idText), body: Data(bytes: bytes, count: length)))
            }
            return result
        }
    }

    private func execute(_ sql: String, locked: Bool = false) {
        let run = { [db] in
            _ = sqlite3_exec(db, sql, nil, nil, nil)
        }
        if locked {
            run()
        } else {
            queue.sync(execute: run)
        }
    }

    private static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Anurja", isDirectory: true)
            .appendingPathComponent("anurja.sqlite")
    }
}

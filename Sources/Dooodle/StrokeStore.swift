import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct Vertex {
    var x: Double
    var y: Double
    var t: Double // unix epoch seconds
}

final class Stroke {
    let id: Int64
    let startedAt: Double
    let colorHex: String
    let width: Double
    var vertices: [Vertex]

    init(id: Int64, startedAt: Double, colorHex: String, width: Double, vertices: [Vertex] = []) {
        self.id = id
        self.startedAt = startedAt
        self.colorHex = colorHex
        self.width = width
        self.vertices = vertices
    }
}

/// SQLite-backed store. Schema:
///   strokes(id, started_at, color, width, cleared_at)
///   vertices(stroke_id, seq, x, y, t)
/// "Clear" only sets cleared_at so history remains queryable.
final class StrokeStore {
    private var db: OpaquePointer?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dooodle", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("dooodle.sqlite").path

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            NSLog("Dooodle: failed to open db at \(path)")
            return
        }
        exec("PRAGMA journal_mode=WAL")
        exec("""
            CREATE TABLE IF NOT EXISTS strokes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                started_at REAL NOT NULL,
                color TEXT NOT NULL,
                width REAL NOT NULL,
                cleared_at REAL
            )
            """)
        exec("""
            CREATE TABLE IF NOT EXISTS vertices (
                stroke_id INTEGER NOT NULL REFERENCES strokes(id),
                seq INTEGER NOT NULL,
                x REAL NOT NULL,
                y REAL NOT NULL,
                t REAL NOT NULL,
                PRIMARY KEY (stroke_id, seq)
            )
            """)
    }

    deinit { sqlite3_close(db) }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            NSLog("Dooodle: sql error: \(err.map { String(cString: $0) } ?? "?")")
            sqlite3_free(err)
        }
    }

    // MARK: - Writes

    func beginStroke(colorHex: String, width: Double, startedAt: Double) -> Int64 {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO strokes (started_at, color, width) VALUES (?,?,?)", -1, &stmt, nil)
        sqlite3_bind_double(stmt, 1, startedAt)
        sqlite3_bind_text(stmt, 2, colorHex, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, width)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        return sqlite3_last_insert_rowid(db)
    }

    func addVertex(strokeId: Int64, seq: Int, _ v: Vertex) {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO vertices (stroke_id, seq, x, y, t) VALUES (?,?,?,?,?)", -1, &stmt, nil)
        sqlite3_bind_int64(stmt, 1, strokeId)
        sqlite3_bind_int(stmt, 2, Int32(seq))
        sqlite3_bind_double(stmt, 3, v.x)
        sqlite3_bind_double(stmt, 4, v.y)
        sqlite3_bind_double(stmt, 5, v.t)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    /// Hide everything from the canvas but keep rows for later querying.
    func clearVisible() {
        exec("UPDATE strokes SET cleared_at = \(Date().timeIntervalSince1970) WHERE cleared_at IS NULL")
    }

    // MARK: - Reads

    func loadVisibleStrokes() -> [Stroke] {
        var strokes: [Int64: Stroke] = [:]
        var order: [Int64] = []

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT id, started_at, color, width FROM strokes WHERE cleared_at IS NULL ORDER BY id", -1, &stmt, nil)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let stroke = Stroke(
                id: id,
                startedAt: sqlite3_column_double(stmt, 1),
                colorHex: String(cString: sqlite3_column_text(stmt, 2)),
                width: sqlite3_column_double(stmt, 3)
            )
            strokes[id] = stroke
            order.append(id)
        }
        sqlite3_finalize(stmt)

        sqlite3_prepare_v2(db, """
            SELECT v.stroke_id, v.x, v.y, v.t FROM vertices v
            JOIN strokes s ON s.id = v.stroke_id
            WHERE s.cleared_at IS NULL
            ORDER BY v.stroke_id, v.seq
            """, -1, &stmt, nil)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            strokes[id]?.vertices.append(Vertex(
                x: sqlite3_column_double(stmt, 1),
                y: sqlite3_column_double(stmt, 2),
                t: sqlite3_column_double(stmt, 3)
            ))
        }
        sqlite3_finalize(stmt)

        return order.compactMap { strokes[$0] }
    }
}

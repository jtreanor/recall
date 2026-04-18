import AppKit
import CryptoKit

struct HistoryItem {
    let id: Int64
    let kind: Kind
    let text: String?
    let imagePath: String?
    let contentHash: String
    let createdAt: Date

    enum Kind: String {
        case text, image
    }
}

final class HistoryStore {
    static let historyLimit = 500

    private let db: Database
    private let imagesDir: URL

    init(db: Database, imagesDir: URL) {
        self.db = db
        self.imagesDir = imagesDir
    }

    convenience init() throws {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let recallDir = support.appendingPathComponent("Recall")
        let imagesDir = recallDir.appendingPathComponent("images")
        try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let db = try Database(path: recallDir.appendingPathComponent("recall.db").path)
        self.init(db: db, imagesDir: imagesDir)
    }

    @discardableResult
    func insert(item: ClipboardItem) throws -> HistoryItem? {
        switch item {
        case .text(let s):       return try insertText(s)
        case .image(let png, _): return try insertImage(png: png)
        }
    }

    func fetchAll() throws -> [HistoryItem] {
        try db.query(
            "SELECT id, created_at, type, text_content, image_path, content_hash FROM items ORDER BY updated_at DESC, id DESC"
        ).compactMap(row(from:))
    }

    func delete(id: Int64) throws {
        if let path = try imagePathFor(id: id) {
            try? FileManager.default.removeItem(atPath: path)
        }
        try db.run("DELETE FROM items WHERE id = ?", .int64(id))
    }

    func pruneToLimit(_ limit: Int) throws {
        let rows = try db.query(
            "SELECT id, image_path FROM items ORDER BY updated_at DESC, id DESC LIMIT -1 OFFSET \(limit)"
        )
        for r in rows {
            guard let id = r["id"]?.int64Value else { continue }
            if let path = r["image_path"]?.stringValue {
                try? FileManager.default.removeItem(atPath: path)
            }
            try db.run("DELETE FROM items WHERE id = ?", .int64(id))
        }
    }

    func count() throws -> Int {
        let rows = try db.query("SELECT COUNT(*) as n FROM items")
        return rows.first?["n"]?.int64Value.map(Int.init) ?? 0
    }

    // MARK: - Private

    private func insertText(_ text: String) throws -> HistoryItem? {
        guard let data = text.data(using: .utf8) else { return nil }
        let hash = sha256(data)
        guard try !hashExists(hash) else { return nil }
        let now = Int64(Date().timeIntervalSince1970)
        try db.run(
            "INSERT INTO items (created_at, updated_at, type, text_content, content_hash) VALUES (?,?,?,?,?)",
            .int64(now), .int64(now), .text("text"), .text(text), .text(hash)
        )
        let id = db.lastInsertRowid
        try pruneToLimit(Self.historyLimit)
        return HistoryItem(id: id, kind: .text, text: text, imagePath: nil, contentHash: hash,
                           createdAt: Date(timeIntervalSince1970: TimeInterval(now)))
    }

    private func insertImage(png: Data) throws -> HistoryItem? {
        let hash = sha256(png)
        guard try !hashExists(hash) else { return nil }
        let filePath = imagesDir.appendingPathComponent("\(hash).png").path
        try png.write(to: URL(fileURLWithPath: filePath))
        let now = Int64(Date().timeIntervalSince1970)
        try db.run(
            "INSERT INTO items (created_at, updated_at, type, image_path, content_hash) VALUES (?,?,?,?,?)",
            .int64(now), .int64(now), .text("image"), .text(filePath), .text(hash)
        )
        let id = db.lastInsertRowid
        try pruneToLimit(Self.historyLimit)
        return HistoryItem(id: id, kind: .image, text: nil, imagePath: filePath, contentHash: hash,
                           createdAt: Date(timeIntervalSince1970: TimeInterval(now)))
    }

    private func hashExists(_ hash: String) throws -> Bool {
        let rows = try db.query("SELECT 1 FROM items WHERE content_hash = ? LIMIT 1", .text(hash))
        return !rows.isEmpty
    }

    private func imagePathFor(id: Int64) throws -> String? {
        let rows = try db.query("SELECT image_path FROM items WHERE id = ?", .int64(id))
        return rows.first?["image_path"]?.stringValue
    }

    private func row(from r: [String: DBValue]) -> HistoryItem? {
        guard let id = r["id"]?.int64Value,
              let typeStr = r["type"]?.stringValue,
              let kind = HistoryItem.Kind(rawValue: typeStr),
              let hash = r["content_hash"]?.stringValue,
              let ts = r["created_at"]?.int64Value else { return nil }
        return HistoryItem(
            id: id, kind: kind,
            text: r["text_content"]?.stringValue,
            imagePath: r["image_path"]?.stringValue,
            contentHash: hash,
            createdAt: Date(timeIntervalSince1970: TimeInterval(ts))
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

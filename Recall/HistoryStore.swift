import AppKit
import CryptoKit

struct HistoryItem {
    let id: Int64
    let kind: Kind
    let text: String?
    let imagePath: String?
    let contentHash: String
    let sourceBundleId: String?
    let createdAt: Date

    enum Kind: String {
        case text, image
    }
}

final class HistoryStore {
    static var historyLimit: Int { SettingsManager.shared.historyLimit }

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
    func insert(item: ClipboardItem, sourceBundleId: String? = nil) throws -> HistoryItem? {
        switch item {
        case .text(let s):       return try insertText(s, sourceBundleId: sourceBundleId)
        case .image(let png, _): return try insertImage(png: png, sourceBundleId: sourceBundleId)
        }
    }

    func fetchAll() throws -> [HistoryItem] {
        try db.query(
            "SELECT id, created_at, type, text_content, image_path, content_hash, source_bundle_id FROM items ORDER BY updated_at DESC, id DESC"
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

    func pruneExpired(_ maxAgeSecs: Int) throws {
        guard maxAgeSecs > 0 else { return }
        let cutoff = Int64((Date().timeIntervalSince1970 - TimeInterval(maxAgeSecs)) * 1_000_000)
        let rows = try db.query(
            "SELECT id, image_path FROM items WHERE updated_at < ?", .int64(cutoff)
        )
        for r in rows {
            if let path = r["image_path"]?.stringValue {
                try? FileManager.default.removeItem(atPath: path)
            }
            if let id = r["id"]?.int64Value {
                try db.run("DELETE FROM items WHERE id = ?", .int64(id))
            }
        }
    }

    func clearAll() throws {
        let rows = try db.query("SELECT image_path FROM items WHERE image_path IS NOT NULL")
        for r in rows {
            if let path = r["image_path"]?.stringValue {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        try db.run("DELETE FROM items")
    }

    func count() throws -> Int {
        let rows = try db.query("SELECT COUNT(*) as n FROM items")
        return rows.first?["n"]?.int64Value.map(Int.init) ?? 0
    }

    // MARK: - Private

    private func insertText(_ text: String, sourceBundleId: String?) throws -> HistoryItem? {
        guard let data = text.data(using: .utf8) else { return nil }
        let hash = sha256(data)
        let now = Int64(Date().timeIntervalSince1970 * 1_000_000)
        if let existing = try itemForHash(hash) {
            try db.run("UPDATE items SET updated_at = ? WHERE id = ?", .int64(now), .int64(existing.id))
            return existing
        }
        let bundleParam: DBParam = sourceBundleId.map { .text($0) } ?? .null
        try db.run(
            "INSERT INTO items (created_at, updated_at, type, text_content, content_hash, source_bundle_id) VALUES (?,?,?,?,?,?)",
            .int64(now), .int64(now), .text("text"), .text(text), .text(hash), bundleParam
        )
        let id = db.lastInsertRowid
        try pruneToLimit(Self.historyLimit)
        try pruneExpired(SettingsManager.shared.itemMaxAgeSecs)
        return HistoryItem(id: id, kind: .text, text: text, imagePath: nil, contentHash: hash,
                           sourceBundleId: sourceBundleId,
                           createdAt: Date(timeIntervalSince1970: TimeInterval(now)))
    }

    private func insertImage(png: Data, sourceBundleId: String?) throws -> HistoryItem? {
        let hash = sha256(png)
        let now = Int64(Date().timeIntervalSince1970 * 1_000_000)
        if let existing = try itemForHash(hash) {
            try db.run("UPDATE items SET updated_at = ? WHERE id = ?", .int64(now), .int64(existing.id))
            return existing
        }
        let filePath = imagesDir.appendingPathComponent("\(hash).png").path
        try png.write(to: URL(fileURLWithPath: filePath))
        let bundleParam: DBParam = sourceBundleId.map { .text($0) } ?? .null
        try db.run(
            "INSERT INTO items (created_at, updated_at, type, image_path, content_hash, source_bundle_id) VALUES (?,?,?,?,?,?)",
            .int64(now), .int64(now), .text("image"), .text(filePath), .text(hash), bundleParam
        )
        let id = db.lastInsertRowid
        try pruneToLimit(Self.historyLimit)
        try pruneExpired(SettingsManager.shared.itemMaxAgeSecs)
        return HistoryItem(id: id, kind: .image, text: nil, imagePath: filePath, contentHash: hash,
                           sourceBundleId: sourceBundleId,
                           createdAt: Date(timeIntervalSince1970: TimeInterval(now)))
    }

    private func itemForHash(_ hash: String) throws -> HistoryItem? {
        let rows = try db.query(
            "SELECT id, created_at, type, text_content, image_path, content_hash, source_bundle_id FROM items WHERE content_hash = ? LIMIT 1",
            .text(hash)
        )
        return rows.first.flatMap(row(from:))
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
            sourceBundleId: r["source_bundle_id"]?.stringValue,
            createdAt: Date(timeIntervalSince1970: TimeInterval(ts))
        )
    }

    // Sets updated_at on all rows — used in tests to simulate aged items.
    func backdateAll(to timestamp: Int64) throws {
        try db.run("UPDATE items SET updated_at = ?", .int64(timestamp))
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

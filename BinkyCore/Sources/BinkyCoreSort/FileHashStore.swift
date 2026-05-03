import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SQLite3

private let sqliteTransient: (@convention(c) (UnsafeMutableRawPointer?) -> Void) = unsafeBitCast(-1, to: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)

/// Persistent store for SHA-256 and perceptual image fingerprints — duplicate detection across sort runs.
public final class FileHashStore: @unchecked Sendable {

    public static let shared = FileHashStore()

    private let dbPath: String
    private let lock = NSLock()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Binky", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        dbPath = base.appendingPathComponent("file_hashes.sqlite3").path
        setupSchema()
    }

    public struct LookupResult: Sendable {
        public var priorPath: String?
        public var isByteDuplicate: Bool
        public var isNearImageDuplicate: Bool

        public init(priorPath: String?, isByteDuplicate: Bool, isNearImageDuplicate: Bool) {
            self.priorPath = priorPath
            self.isByteDuplicate = isByteDuplicate
            self.isNearImageDuplicate = isNearImageDuplicate
        }
    }

    // MARK: - API

    public func lookup(sha256: String, perceptual: UInt64?, isImage: Bool) -> LookupResult {
        lock.lock()
        defer { lock.unlock() }
        var out = LookupResult(priorPath: nil, isByteDuplicate: false, isNearImageDuplicate: false)
        guard let db = openDB() else { return out }
        defer { sqlite3_close(db) }

        if let rowPath = Self.fetchPath(db: db, sha256: sha256) {
            out.priorPath = rowPath
            out.isByteDuplicate = true
            return out
        }

        if isImage, let p = perceptual, let near = Self.scanNearImageDuplicate(db: db, target: p) {
            out.priorPath = near
            out.isNearImageDuplicate = true
        }
        return out
    }

    public func recordSortedFile(url: URL, sha256: String, byteSize: Int64, perceptual: UInt64?, isImage: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let db = openDB() else { return }
        defer { sqlite3_close(db) }
        let phex: String? = perceptual.map { String(format: "%016llx", $0) }
        let ts = Date().timeIntervalSince1970
        let sql = """
        INSERT INTO file_hashes (sha256, path, byte_size, perceptual_hex, is_image, first_seen)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(sha256) DO UPDATE SET
          path = excluded.path,
          byte_size = excluded.byte_size,
          perceptual_hex = excluded.perceptual_hex,
          is_image = excluded.is_image;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sha256, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, url.path, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 3, byteSize)
        if let phex {
            sqlite3_bind_text(stmt, 4, phex, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_int(stmt, 5, isImage ? 1 : 0)
        sqlite3_bind_double(stmt, 6, ts)
        _ = sqlite3_step(stmt)
    }

    public func digestFile(at url: URL) throws -> (sha256: String, perceptual: UInt64?, isImage: Bool) {
        guard let fh = try? FileHandle(forReadingFrom: url) else {
            throw NSError(domain: "FileHashStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read file"])
        }
        defer { try? fh.close() }
        var hasher = SHA256()
        while true {
            let chunk = try fh.read(upToCount: 512 * 1024)
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let sha = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.lowercased()
        let isImg = Self.isRasterImageExtension(ext)
        let p: UInt64? = isImg ? Self.perceptualHash(url: url) : nil
        return (sha, p, isImg)
    }

    // MARK: - DB

    private func openDB() -> OpaquePointer? {
        var db: OpaquePointer?
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            return nil
        }
        return db
    }

    private func setupSchema() {
        lock.lock()
        defer { lock.unlock() }
        guard let db = openDB() else { return }
        defer { sqlite3_close(db) }
        let ddl = """
        CREATE TABLE IF NOT EXISTS file_hashes (
            sha256 TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            byte_size INTEGER NOT NULL,
            perceptual_hex TEXT,
            is_image INTEGER NOT NULL DEFAULT 0,
            first_seen REAL NOT NULL
        );
        """
        _ = sqlite3_exec(db, ddl, nil, nil, nil)
    }

    private static func fetchPath(db: OpaquePointer, sha256: String) -> String? {
        let sql = "SELECT path FROM file_hashes WHERE sha256 = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sha256, -1, sqliteTransient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return String(cString: sqlite3_column_text(stmt, 0))
    }

    private static func scanNearImageDuplicate(db: OpaquePointer, target: UInt64) -> String? {
        let sql = "SELECT path, perceptual_hex FROM file_hashes WHERE is_image = 1 AND perceptual_hex IS NOT NULL;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = String(cString: sqlite3_column_text(stmt, 0))
            let hex = String(cString: sqlite3_column_text(stmt, 1))
            guard let val = UInt64(hex, radix: 16) else { continue }
            if (target ^ val).nonzeroBitCount <= 10 {
                return path
            }
        }
        return nil
    }

    // MARK: - Perceptual hash

    private static func isRasterImageExtension(_ ext: String) -> Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"].contains(ext)
    }

    private static func perceptualHash(url: URL) -> UInt64? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return dHash64(from: cg)
    }

    private static func dHash64(from cgImage: CGImage) -> UInt64? {
        let w = 9
        let h = 8
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: w * h)
        var hash: UInt64 = 0
        var bitIndex: UInt64 = 0
        for y in 0..<h {
            for x in 0..<(w - 1) {
                guard bitIndex < 64 else { break }
                let left = Int(ptr[y * w + x])
                let right = Int(ptr[y * w + x + 1])
                if left > right {
                    hash |= (1 << bitIndex)
                }
                bitIndex += 1
            }
        }
        return hash
    }

    /// Rows in the duplicate-memory database (for Settings).
    public func storedRecordCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let db = openDB() else { return 0 }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM file_hashes;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// Clears all remembered fingerprints (user explicitly requests this in Settings).
    public func clearAllRecords() {
        lock.lock()
        defer { lock.unlock() }
        guard let db = openDB() else { return }
        defer { sqlite3_close(db) }
        _ = sqlite3_exec(db, "DELETE FROM file_hashes;", nil, nil, nil)
    }
}

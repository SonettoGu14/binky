import Darwin
import Foundation

/// Cooperative exclusive lock shared by Binky.app and `binky` CLI so concurrent sorts never race (`~/Library/Application Support/Binky/sort.lock`).
public final class SortCrossProcessLock: @unchecked Sendable {
    private var fd: Int32 = -1
    private let path: URL

    public nonisolated init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = support.appendingPathComponent("Binky", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        path = dir.appendingPathComponent("sort.lock", isDirectory: false)
        fd = path.path.withCString { open($0, O_CREAT | O_RDWR, 0o644) }
    }

    public nonisolated var lockPOSIXPath: String {
        path.path
    }

    /// Returns `false` when another process holds the flock (or creation failed).
    @discardableResult
    public nonisolated func tryLock() -> Bool {
        guard fd >= 0 else { return false }
        return flock(fd, LOCK_EX | LOCK_NB) == 0
    }

    /// Releases the flock and closes the FD.
    public nonisolated func unlock() {
        guard fd >= 0 else { return }
        _ = flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    deinit {
        unlock()
    }
}

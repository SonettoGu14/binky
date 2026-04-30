import Foundation
import os

/// Debug-level timing for compression phases. Enable **Debug** logs for subsystem `com.binky.app` in Console.app to compare runs (e.g. Smart Quality on vs off).
enum CompressionTiming {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.binky.app",
        category: "CompressionTiming"
    )

    static func logPhase(_ name: String, startedAt: CFAbsoluteTime) {
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
        log.debug("\(name, privacy: .public) \(String(format: "%.3f", elapsed))s")
    }

    /// One-line context when investigating “slower now” (Smart Quality, Auto format, caps, batch concurrency).
    static func logReproContext(media: String, smartQuality: Bool, extra: String = "") {
        if extra.isEmpty {
            log.debug("repro context: media=\(media, privacy: .public) smartQ=\(smartQuality, privacy: .public)")
        } else {
            log.debug("repro context: media=\(media, privacy: .public) smartQ=\(smartQuality, privacy: .public) \(extra, privacy: .public)")
        }
    }
}

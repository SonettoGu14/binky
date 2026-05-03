import Foundation

/// Tiny bridge until the CLI adopts a fuller async-main story.
enum BinkyCLIAsync {
    final class Box<T>: @unchecked Sendable {
        var value: T!
    }

    /// Runs `work` synchronously from a sync entrypoint (`main`).
    nonisolated static func runBlocking<T>(_ work: @escaping @Sendable () async -> T) -> T {
        let box = Box<T>()
        let sem = DispatchSemaphore(value: 0)
        Task {
            box.value = await work()
            sem.signal()
        }
        sem.wait()
        return box.value
    }
}

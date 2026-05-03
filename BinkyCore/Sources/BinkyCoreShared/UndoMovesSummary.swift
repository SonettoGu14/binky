import Foundation

/// Summary of undoing a stored list of `(destination, source)` pairs (reverses sort moves).
public struct UndoMovesSummary: Sendable {
    public let attempted: Int
    public let failures: Int

    public init(attempted: Int, failures: Int) {
        self.attempted = attempted
        self.failures = failures
    }
}

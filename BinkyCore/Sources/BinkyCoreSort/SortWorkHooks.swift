import BinkyCoreShared
import Foundation

/// UI / expiry hooks injected by the GUI app so the sort pipeline stays headless inside BinkyCoreSort.
public struct SortWorkHooks: Sendable {

    /// Low Power / thermal full pause UX (typically wires to ``SortProgressTracker``).
    public var onEnergyHold: (@Sendable (SortEnergyHoldKind) -> Void)?
    /// Called when energy throttle resumes after a hold.
    public var onEnergyHoldClear: (@Sendable () -> Void)?

    /// Optional “New” tag TTL registration (typically ``NewTagExpiryService`` on MainActor).
    public var registerNewTagExpiry: (@Sendable (URL, Int) async -> Void)?

    public nonisolated init(
        onEnergyHold: (@Sendable (SortEnergyHoldKind) -> Void)? = nil,
        onEnergyHoldClear: (@Sendable () -> Void)? = nil,
        registerNewTagExpiry: (@Sendable (URL, Int) async -> Void)? = nil
    ) {
        self.onEnergyHold = onEnergyHold
        self.onEnergyHoldClear = onEnergyHoldClear
        self.registerNewTagExpiry = registerNewTagExpiry
    }

    /// No MainActor integration (CLI headless sorts).
    public static let detached: SortWorkHooks = SortWorkHooks()
}

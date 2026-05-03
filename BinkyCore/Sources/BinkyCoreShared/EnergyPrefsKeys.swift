import Foundation

// MARK: - Energy (large-batch sorting / thermal)

/// `UserDefaults` keys for energy behavior (also used by CLI / ``EnergyConditions``).
public enum EnergySettingsKey {
    public static let pauseOnLowPowerMode = "energy.pauseOnLowPowerMode"
    public static let pauseOnThermalCritical = "energy.pauseOnThermalCritical"
    public static let bigBatchThreshold = "energy.bigBatchThreshold"
    public static let throttleProfile = "energy.throttleProfile"
}

public enum EnergyThrottleProfile: String, CaseIterable, Identifiable, Sendable {
    case auto
    case gentle
    case aggressive

    public var id: String { rawValue }
}

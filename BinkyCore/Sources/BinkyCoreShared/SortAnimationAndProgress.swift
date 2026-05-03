import Foundation

/// Visual buckets for organizer empty-state “fly to folder” animation (images / videos / documents only).
public enum SortAnimationBucket: String, Sendable, Equatable {
    case images
    case videos
    case documents
}

public enum SortProgressEvent: Sendable {
    case batchStarted(total: Int)
    case fileStarted(path: String, displayName: String, animationBucket: SortAnimationBucket)
    case fileFinished(path: String)
    case batchEnded
}

/// Energy / thermal hold while a sort is running (distinct from user Pause).
public enum SortEnergyHoldKind: Equatable, Sendable {
    case none
    case thermal
    case lowPower
}

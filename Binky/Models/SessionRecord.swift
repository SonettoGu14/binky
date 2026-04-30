import Foundation

struct SessionRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let fileCount: Int
    let totalBytesSaved: Int64
    let formats: [String]
    /// JSON-encoded `CompressionBatchSummary` for “Open summary” in History; nil for records saved before this feature.
    var batchSummaryData: Data?
}

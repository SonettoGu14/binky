import Foundation

struct SessionRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let fileCount: Int
    /// Byte size of moved files at destination (organizer); legacy records used `totalBytesSaved`.
    let totalBytesMoved: Int64
    let formats: [String]
    var batchSummaryData: Data?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, fileCount, formats, batchSummaryData
        case totalBytesMoved
        case legacyTotalBytesSaved = "totalBytesSaved"
    }

    init(id: UUID, timestamp: Date, fileCount: Int, totalBytesMoved: Int64, formats: [String], batchSummaryData: Data?) {
        self.id = id
        self.timestamp = timestamp
        self.fileCount = fileCount
        self.totalBytesMoved = totalBytesMoved
        self.formats = formats
        self.batchSummaryData = batchSummaryData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        fileCount = try c.decode(Int.self, forKey: .fileCount)
        formats = try c.decodeIfPresent([String].self, forKey: .formats) ?? []
        batchSummaryData = try c.decodeIfPresent(Data.self, forKey: .batchSummaryData)
        if let b = try c.decodeIfPresent(Int64.self, forKey: .totalBytesMoved) {
            totalBytesMoved = b
        } else {
            totalBytesMoved = try c.decodeIfPresent(Int64.self, forKey: .legacyTotalBytesSaved) ?? 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(fileCount, forKey: .fileCount)
        try c.encode(totalBytesMoved, forKey: .totalBytesMoved)
        try c.encode(formats, forKey: .formats)
        try c.encodeIfPresent(batchSummaryData, forKey: .batchSummaryData)
    }
}

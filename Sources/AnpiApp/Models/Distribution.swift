import Foundation
import GRDB

/// 配布イベント（物資名・日時）
struct Distribution: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var itemName: String
    var createdAt: Date
    var totalCount: Int   // 配布対象の避難者数
    var deliveredCount: Int  // 配布済み人数

    static let databaseTableName = "distribution"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// 配布チェック（誰に配ったか）
struct DistributionCheckItem: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var distributionId: Int64
    var evacueeId: Int64
    var isDelivered: Bool
    var deliveredAt: Date?

    static let databaseTableName = "distributionCheckItem"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

import Foundation
import GRDB

final class FamilyGroupService {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - 家族候補検索

    /// 名字×丁目レベル住所で既存登録者の候補を検索する
    /// - Returns: 候補となる EvacueeRecord の配列（自分自身は除く）
    func findCandidates(familyName: String, addressBlock: String, excludingId: Int64? = nil) throws -> [EvacueeRecord] {
        guard !familyName.isEmpty, !addressBlock.isEmpty else { return [] }
        return try dbQueue.read { db in
            var query = EvacueeRecord
                .filter(Column("familyName") == familyName)
                .filter(Column("addressBlock") == addressBlock)
            if let id = excludingId {
                query = query.filter(Column("id") != id)
            }
            return try query.fetchAll(db)
        }
    }

    // MARK: - グループ操作

    /// 新規家族グループを作成し、IDを返す
    func createGroup(representativeName: String) throws -> String {
        let groupId = UUID().uuidString
        try dbQueue.write { db in
            var group = FamilyGroup(
                id: groupId,
                representativeName: representativeName,
                memberCount: 1,
                createdAt: Date()
            )
            try group.save(db)
        }
        return groupId
    }

    /// 既存グループにメンバーを追加（memberCount +1）
    func addToGroup(groupId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE familyGroup SET memberCount = memberCount + 1 WHERE id = ?",
                arguments: [groupId]
            )
        }
    }

    /// グループの全メンバーを取得
    func fetchMembers(groupId: String) throws -> [EvacueeRecord] {
        try dbQueue.read { db in
            try EvacueeRecord
                .filter(Column("familyGroupId") == groupId)
                .fetchAll(db)
        }
    }
}

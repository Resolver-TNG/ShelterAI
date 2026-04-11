import Foundation
import GRDB

final class DatabaseService: ObservableObject {
    private let dbQueue: DatabaseQueue

    init() throws {
        let url = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("anpi.sqlite")
        dbQueue = try DatabaseQueue(path: url.path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "evacueeRecord") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("dateOfBirth", .datetime).notNull()
                t.column("address", .text).notNull()
                t.column("injuryStatus", .text).notNull()
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("isEmergencyMode", .boolean).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v3_phase2_fields") { db in
            try db.alter(table: "evacueeRecord") { t in
                t.add(column: "familyName", .text).notNull().defaults(to: "")
                t.add(column: "addressBlock", .text).notNull().defaults(to: "")
                t.add(column: "gender", .text).notNull().defaults(to: "unspecified")
                t.add(column: "ageGroup", .text).notNull().defaults(to: "adult")
                t.add(column: "specialNeedsJSON", .text).notNull().defaults(to: "[]")
                t.add(column: "familyGroupId", .text)
            }
            try db.create(table: "familyGroup", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("representativeName", .text).notNull()
                t.column("memberCount", .integer).notNull().defaults(to: 1)
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v2_distribution") { db in
            try db.create(table: "distribution") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("itemName", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("totalCount", .integer).notNull().defaults(to: 0)
                t.column("deliveredCount", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "distributionCheckItem") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("distributionId", .integer).notNull().references("distribution", onDelete: .cascade)
                t.column("evacueeId", .integer).notNull().references("evacueeRecord", onDelete: .cascade)
                t.column("isDelivered", .boolean).notNull().defaults(to: false)
                t.column("deliveredAt", .datetime)
            }
        }

        migrator.registerMigration("v4_card_type") { db in
            try db.alter(table: "evacueeRecord") { t in
                t.add(column: "cardType", .text).notNull().defaults(to: CardType.other.rawValue)
            }
        }

        migrator.registerMigration("v5_injury_locations") { db in
            try db.alter(table: "evacueeRecord") { t in
                t.add(column: "injuryLocationsJSON", .text).notNull().defaults(to: "[]")
            }
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - EvacueeRecord

    func save(_ record: inout EvacueeRecord) throws {
        try dbQueue.write { db in try record.save(db) }
    }

    func fetchAll() throws -> [EvacueeRecord] {
        try dbQueue.read { db in try EvacueeRecord.fetchAll(db) }
    }

    func deleteAll() throws {
        try dbQueue.write { db in _ = try EvacueeRecord.deleteAll(db) }
    }

    /// 個別避難者レコードを削除
    func delete(_ record: EvacueeRecord) throws {
        try dbQueue.write { db in
            _ = try record.delete(db)
        }
    }

    func deleteTestData() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM evacueeRecord WHERE isEmergencyMode = 0")
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in try EvacueeRecord.fetchCount(db) }
    }

    func findFamilyCandidates(familyName: String, addressBlock: String) throws -> [EvacueeRecord] {
        try dbQueue.read { db in
            try EvacueeRecord
                .filter(Column("familyName") == familyName)
                .filter(Column("addressBlock") == addressBlock)
                .fetchAll(db)
        }
    }

    func fetchFamilyMembers(groupId: String) throws -> [EvacueeRecord] {
        try dbQueue.read { db in
            try EvacueeRecord
                .filter(Column("familyGroupId") == groupId)
                .fetchAll(db)
        }
    }

    // MARK: - Distribution

    /// 新しい配布イベントを作成し、全避難者分のチェック項目を生成
    func createDistribution(itemName: String) throws -> Distribution {
        try dbQueue.write { db in
            let evacuees = try EvacueeRecord.fetchAll(db)
            var dist = Distribution(
                itemName: itemName,
                createdAt: Date(),
                totalCount: evacuees.count,
                deliveredCount: 0
            )
            try dist.save(db)

            guard let distId = dist.id else { return dist }

            for evacuee in evacuees {
                guard let evacueeId = evacuee.id else { continue }
                var item = DistributionCheckItem(
                    distributionId: distId,
                    evacueeId: evacueeId,
                    isDelivered: false,
                    deliveredAt: nil
                )
                try item.save(db)
            }
            return dist
        }
    }

    /// 配布イベント一覧
    func fetchAllDistributions() throws -> [Distribution] {
        try dbQueue.read { db in
            try Distribution.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    /// 配布チェック項目を現在の避難者リストと同期する
    ///
    /// - 新規避難者には `DistributionCheckItem` を追加（isDelivered=false）
    /// - 削除済み避難者の orphan な `DistributionCheckItem` を削除
    /// - `Distribution.totalCount` / `deliveredCount` を実態に合わせて再集計
    ///
    /// 配布作成後に避難者が追加・削除された場合でもリストが正しく反映されるようにする。
    /// 戻り値は同期で実際に変更があったかどうか（呼び出し側のロギング用、未使用でも可）。
    @discardableResult
    func syncDistributionCheckItems(distributionId: Int64) throws -> Bool {
        try dbQueue.write { db in
            // 配布レコード取得（存在しなければ何もしない）
            guard var dist = try Distribution.fetchOne(db, key: distributionId) else {
                return false
            }

            // 現在の避難者全員
            let evacuees = try EvacueeRecord.fetchAll(db)
            let currentEvacueeIds = Set(evacuees.compactMap { $0.id })

            // 既存のチェック項目
            let existingItems = try DistributionCheckItem
                .filter(Column("distributionId") == distributionId)
                .fetchAll(db)
            let existingEvacueeIds = Set(existingItems.map { $0.evacueeId })

            var changed = false

            // 1. 新規避難者: チェック項目を追加
            let toAdd = currentEvacueeIds.subtracting(existingEvacueeIds)
            for evacueeId in toAdd {
                var item = DistributionCheckItem(
                    distributionId: distributionId,
                    evacueeId: evacueeId,
                    isDelivered: false,
                    deliveredAt: nil
                )
                try item.save(db)
                changed = true
            }

            // 2. 削除済み避難者: orphan な項目を削除
            //    （onDelete: .cascade で本来消えるが、念のため整合性を担保）
            let toRemove = existingEvacueeIds.subtracting(currentEvacueeIds)
            if !toRemove.isEmpty {
                let orphanItems = existingItems.filter { toRemove.contains($0.evacueeId) }
                for item in orphanItems {
                    _ = try item.delete(db)
                }
                changed = true
            }

            // 3. totalCount / deliveredCount を再集計
            let newTotal = try DistributionCheckItem
                .filter(Column("distributionId") == distributionId)
                .fetchCount(db)
            let newDelivered = try DistributionCheckItem
                .filter(Column("distributionId") == distributionId)
                .filter(Column("isDelivered") == true)
                .fetchCount(db)

            if dist.totalCount != newTotal || dist.deliveredCount != newDelivered {
                dist.totalCount = newTotal
                dist.deliveredCount = newDelivered
                try dist.update(db)
                changed = true
            }

            return changed
        }
    }

    /// 配布チェック項目（避難者情報付き）
    func fetchCheckItems(distributionId: Int64) throws -> [(DistributionCheckItem, EvacueeRecord)] {
        try dbQueue.read { db in
            let items = try DistributionCheckItem
                .filter(Column("distributionId") == distributionId)
                .fetchAll(db)
            return try items.compactMap { item in
                guard let evacuee = try EvacueeRecord.fetchOne(db, key: item.evacueeId) else { return nil }
                return (item, evacuee)
            }
        }
    }

    /// チェック状態を更新し、配布済み数を再集計
    func toggleDelivery(item: DistributionCheckItem) throws {
        try dbQueue.write { db in
            var updated = item
            updated.isDelivered = !item.isDelivered
            updated.deliveredAt = updated.isDelivered ? Date() : nil
            try updated.save(db)

            // deliveredCount を再集計
            let delivered = try DistributionCheckItem
                .filter(Column("distributionId") == item.distributionId)
                .filter(Column("isDelivered") == true)
                .fetchCount(db)

            try db.execute(
                sql: "UPDATE distribution SET deliveredCount = ? WHERE id = ?",
                arguments: [delivered, item.distributionId]
            )
        }
    }

    /// 配布イベント削除
    func deleteDistribution(_ distribution: Distribution) throws {
        try dbQueue.write { db in _ = try distribution.delete(db) }
    }

    // MARK: - Analytics

    /// 全レコードの集計統計を返す
    ///
    /// `specialNeedsJSON` は JSON 文字列なので SQL 集計せず、
    /// `fetchAll()` してから Swift 側で `ShelterAnalytics.computeStats(from:)` に委譲する。
    func fetchStats() throws -> ShelterStats {
        let records = try fetchAll()
        return ShelterAnalytics.computeStats(from: records)
    }

    /// 年齢グループ別カウント
    func countByAgeGroup() throws -> [AgeGroup: Int] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT ageGroup, COUNT(*) AS c FROM evacueeRecord GROUP BY ageGroup"
            )
            var result: [AgeGroup: Int] = [:]
            for row in rows {
                guard let raw: String = row["ageGroup"],
                      let group = AgeGroup(rawValue: raw),
                      let count: Int = row["c"] else { continue }
                result[group] = count
            }
            return result
        }
    }

    /// 怪我ステータス別カウント
    func countByInjuryStatus() throws -> [String: Int] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT injuryStatus, COUNT(*) AS c FROM evacueeRecord GROUP BY injuryStatus"
            )
            var result: [String: Int] = [:]
            for row in rows {
                guard let key: String = row["injuryStatus"],
                      let count: Int = row["c"] else { continue }
                result[key] = count
            }
            return result
        }
    }

    /// 性別カウント
    func countByGender() throws -> [Gender: Int] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT gender, COUNT(*) AS c FROM evacueeRecord GROUP BY gender"
            )
            var result: [Gender: Int] = [:]
            for row in rows {
                guard let raw: String = row["gender"],
                      let g = Gender(rawValue: raw),
                      let count: Int = row["c"] else { continue }
                result[g] = count
            }
            return result
        }
    }

    /// 配慮事項別カウント
    ///
    /// `specialNeedsJSON` は JSON 文字列なので SQL 集計不可。
    /// `fetchAll()` してから Swift 側でパースして集計する。
    func countBySpecialNeeds() throws -> [SpecialNeed: Int] {
        let records = try fetchAll()
        var result: [SpecialNeed: Int] = [:]
        for r in records {
            for need in r.specialNeeds {
                result[need, default: 0] += 1
            }
        }
        return result
    }
}

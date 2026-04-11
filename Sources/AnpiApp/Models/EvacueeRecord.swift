import Foundation
import GRDB

// MARK: - Enums

enum Gender: String, CaseIterable, Codable {
    case female, male, other, unspecified
    var label: String {
        switch self {
        case .female: return "女性"
        case .male: return "男性"
        case .other: return "その他"
        case .unspecified: return "未回答"
        }
    }
}

enum AgeGroup: String, CaseIterable, Codable {
    case infant, child, adult, elderly
    var label: String {
        switch self {
        case .infant: return "乳幼児（0-3歳）"
        case .child: return "子供（4-15歳）"
        case .adult: return "成人"
        case .elderly: return "高齢者（65歳以上）"
        }
    }
}

enum SpecialNeed: String, CaseIterable, Codable {
    case sanitary       // 生理用品が必要
    case infantCare     // 乳幼児ケア用品が必要
    case wheelchair     // 車椅子
    case other
    var label: String {
        switch self {
        case .sanitary: return "🩸 生理用品"
        case .infantCare: return "👶 乳幼児ケア"
        case .wheelchair: return "♿ 車椅子"
        case .other: return "その他配慮事項"
        }
    }
    var icon: String {
        switch self {
        case .sanitary: return "🩸"
        case .infantCare: return "👶"
        case .wheelchair: return "♿"
        case .other: return "⚠️"
        }
    }
}

// MARK: - EvacueeRecord

struct EvacueeRecord: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var name: String
    var dateOfBirth: Date
    var address: String
    var injuryStatus: String
    var latitude: Double?
    var longitude: Double?
    var isEmergencyMode: Bool
    var createdAt: Date

    // Phase 2 フィールド
    var familyName: String = ""
    var addressBlock: String = ""
    var gender: Gender = .unspecified
    var ageGroup: AgeGroup = .adult
    var specialNeedsJSON: String = "[]"   // JSON文字列でDB保存
    var familyGroupId: String? = nil

    // Phase 3 フィールド
    var cardType: String = CardType.other.rawValue   // Gemmaが判定したカード種別

    // Phase 4 フィールド
    var injuryLocationsJSON: String = "[]"   // 怪我部位（[String] を JSON 文字列で DB 保存）

    static let databaseTableName = "evacueeRecord"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - specialNeeds 変換ヘルパー

    var specialNeeds: [SpecialNeed] {
        get {
            (try? JSONDecoder().decode([SpecialNeed].self, from: Data(specialNeedsJSON.utf8))) ?? []
        }
        set {
            specialNeedsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
        }
    }

    // MARK: - injuryLocations 変換ヘルパー

    /// 怪我部位の一覧。ストレージは `injuryLocationsJSON` に JSON 文字列として保存される。
    /// computed property なので Codable の自動生成 CodingKeys には含まれず、
    /// GRDB のカラムマッピング対象からも除外される。
    var injuryLocations: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: Data(injuryLocationsJSON.utf8))) ?? []
        }
        set {
            injuryLocationsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
        }
    }
}

// MARK: - FamilyGroup

struct FamilyGroup: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: String = UUID().uuidString
    var representativeName: String
    var memberCount: Int = 1
    var createdAt: Date

    static let databaseTableName = "familyGroup"
}

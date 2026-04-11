import Foundation

/// テストモード用のサンプルデータ投入機能
///
/// デモ動画撮影を想定したリアルなサンプルセットを生成・投入する。
/// 家族グループ推論・ShelterAnalytics・配慮事項表示などを一通りデモできるよう、
/// 同住所ブロックのグループ／高齢者・乳幼児・怪我人・外国人などをバランスよく含める。
///
/// すべて `isEmergencyMode = false`（テストモード）で投入される。
enum SampleDataSeeder {

    // MARK: - Public

    /// サンプルデータを生成（DBには投入しない）
    static func generate() -> [EvacueeRecord] {
        let now = Date()
        var records: [EvacueeRecord] = []

        // 同住所ブロック（家族）グループを複数構成し、家族グループ推論を見せる
        // ブロックA: 渋谷区恵比寿1丁目 — 田中家（祖母 + 夫婦 + 子）
        records.append(make(
            name: "田中 ハナ",
            dob: birthday(yearsAgo: 78),
            address: "東京都渋谷区恵比寿1丁目3番5号",
            injury: "なし",
            gender: .female, age: .elderly,
            needs: [.wheelchair, .other],
            createdAt: now.addingTimeInterval(-60 * 50)
        ))
        records.append(make(
            name: "田中 健一",
            dob: birthday(yearsAgo: 45),
            address: "東京都渋谷区恵比寿1丁目3番5号",
            injury: "軽傷（右腕擦り傷）",
            gender: .male, age: .adult,
            needs: [],
            createdAt: now.addingTimeInterval(-60 * 48),
            injuryLocations: ["右腕"]
        ))
        records.append(make(
            name: "田中 美咲",
            dob: birthday(yearsAgo: 42),
            address: "東京都渋谷区恵比寿1丁目3番5号",
            injury: "なし",
            gender: .female, age: .adult,
            needs: [.sanitary],
            createdAt: now.addingTimeInterval(-60 * 47)
        ))
        records.append(make(
            name: "田中 蒼",
            dob: birthday(yearsAgo: 8),
            address: "東京都渋谷区恵比寿1丁目3番5号",
            injury: "なし",
            gender: .male, age: .child,
            needs: [],
            createdAt: now.addingTimeInterval(-60 * 46)
        ))

        // ブロックB: 渋谷区恵比寿2丁目 — 佐藤家（夫婦 + 乳幼児）
        records.append(make(
            name: "佐藤 直樹",
            dob: birthday(yearsAgo: 34),
            address: "東京都渋谷区恵比寿2丁目8番2号",
            injury: "なし",
            gender: .male, age: .adult,
            needs: [],
            createdAt: now.addingTimeInterval(-60 * 40)
        ))
        records.append(make(
            name: "佐藤 由香",
            dob: birthday(yearsAgo: 32),
            address: "東京都渋谷区恵比寿2丁目8番2号",
            injury: "中程度（足首捻挫・要受診）",
            gender: .female, age: .adult,
            needs: [.sanitary, .infantCare],
            createdAt: now.addingTimeInterval(-60 * 39),
            injuryLocations: ["右脚"]
        ))
        records.append(make(
            name: "佐藤 ひまり",
            dob: birthday(yearsAgo: 1),
            address: "東京都渋谷区恵比寿2丁目8番2号",
            injury: "なし",
            gender: .female, age: .infant,
            needs: [.infantCare],
            createdAt: now.addingTimeInterval(-60 * 38)
        ))

        // ブロックC: 渋谷区恵比寿西1丁目 — 鈴木家（高齢夫婦）
        records.append(make(
            name: "鈴木 武雄",
            dob: birthday(yearsAgo: 82),
            address: "東京都渋谷区恵比寿西1丁目12番4号",
            injury: "重傷（頭部打撲・救急搬送要）",
            gender: .male, age: .elderly,
            needs: [.other],
            createdAt: now.addingTimeInterval(-60 * 35),
            injuryLocations: ["頭部"]
        ))
        records.append(make(
            name: "鈴木 静子",
            dob: birthday(yearsAgo: 79),
            address: "東京都渋谷区恵比寿西1丁目12番4号",
            injury: "軽傷（膝擦過）",
            gender: .female, age: .elderly,
            needs: [.wheelchair],
            createdAt: now.addingTimeInterval(-60 * 34),
            injuryLocations: ["左脚"]
        ))

        // ブロックD: 渋谷区広尾3丁目 — 山本家（母子）
        records.append(make(
            name: "山本 麻衣",
            dob: birthday(yearsAgo: 29),
            address: "東京都渋谷区広尾3丁目5番1号",
            injury: "なし",
            gender: .female, age: .adult,
            needs: [.sanitary, .infantCare],
            createdAt: now.addingTimeInterval(-60 * 30)
        ))
        records.append(make(
            name: "山本 颯太",
            dob: birthday(yearsAgo: 2),
            address: "東京都渋谷区広尾3丁目5番1号",
            injury: "なし",
            gender: .male, age: .infant,
            needs: [.infantCare],
            createdAt: now.addingTimeInterval(-60 * 29)
        ))

        // 単独避難者（外国人住民を含めて多様性を出す）
        records.append(make(
            name: "Maria Santos",
            dob: birthday(yearsAgo: 36),
            address: "東京都渋谷区代官山町2丁目4番8号",
            injury: "なし",
            gender: .female, age: .adult,
            needs: [.sanitary],
            createdAt: now.addingTimeInterval(-60 * 25)
        ))
        records.append(make(
            name: "Wei Chen",
            dob: birthday(yearsAgo: 41),
            address: "東京都渋谷区代官山町2丁目4番8号",
            injury: "軽傷（手指切創）",
            gender: .male, age: .adult,
            needs: [],
            createdAt: now.addingTimeInterval(-60 * 24),
            injuryLocations: ["右手"]
        ))

        // 単独避難者（高齢者・成人）
        records.append(make(
            name: "高橋 良子",
            dob: birthday(yearsAgo: 71),
            address: "東京都渋谷区神宮前4丁目1番3号",
            injury: "なし",
            gender: .female, age: .elderly,
            needs: [.wheelchair],
            createdAt: now.addingTimeInterval(-60 * 22)
        ))
        records.append(make(
            name: "渡辺 翔",
            dob: birthday(yearsAgo: 24),
            address: "東京都渋谷区神宮前4丁目1番3号",
            injury: "中程度（左肩脱臼疑い）",
            gender: .male, age: .adult,
            needs: [],
            createdAt: now.addingTimeInterval(-60 * 21),
            injuryLocations: ["肩", "左腕"]
        ))
        records.append(make(
            name: "伊藤 芽衣",
            dob: birthday(yearsAgo: 16),
            address: "東京都渋谷区神宮前4丁目1番3号",
            injury: "なし",
            gender: .female, age: .child,
            needs: [.sanitary],
            createdAt: now.addingTimeInterval(-60 * 20)
        ))

        // 単身高齢者（独居）
        records.append(make(
            name: "中村 義男",
            dob: birthday(yearsAgo: 88),
            address: "東京都渋谷区松濤1丁目9番2号",
            injury: "なし",
            gender: .male, age: .elderly,
            needs: [.wheelchair, .other],
            createdAt: now.addingTimeInterval(-60 * 18)
        ))

        return records
    }

    /// 生成したサンプルデータをDBに一括投入する
    /// - Parameter db: 投入先の `DatabaseService`
    static func seed(into db: DatabaseService) throws {
        let samples = generate()
        for var record in samples {
            try db.save(&record)
        }
    }

    // MARK: - Internal Helpers

    /// `EvacueeRecord` を組み立てるファクトリ
    /// `familyName` / `addressBlock` は `AddressNormalizer` から導出する。
    private static func make(
        name: String,
        dob: Date,
        address: String,
        injury: String,
        gender: Gender,
        age: AgeGroup,
        needs: [SpecialNeed],
        createdAt: Date,
        injuryLocations: [String] = []
    ) -> EvacueeRecord {
        // 東京駅近辺をベースに、サンプルらしい揺らぎを与える
        let lat = 35.6762 + Double.random(in: -0.02...0.02)
        let lng = 139.6503 + Double.random(in: -0.02...0.02)

        var record = EvacueeRecord(
            name: name,
            dateOfBirth: dob,
            address: address,
            injuryStatus: injury,
            latitude: lat,
            longitude: lng,
            isEmergencyMode: false,
            createdAt: createdAt
        )
        record.familyName = AddressNormalizer.extractFamilyName(name)
        record.addressBlock = AddressNormalizer.normalize(address)
        record.gender = gender
        record.ageGroup = age
        record.specialNeeds = needs
        record.cardType = CardType.other.rawValue
        record.injuryLocations = injuryLocations
        return record
    }

    /// 生年月日を「N年前の今日」で生成
    private static func birthday(yearsAgo years: Int) -> Date {
        let cal = Calendar(identifier: .gregorian)
        return cal.date(byAdding: .year, value: -years, to: Date()) ?? Date()
    }
}

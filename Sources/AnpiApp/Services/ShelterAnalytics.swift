import Foundation

// MARK: - Stats / Estimate Types

/// 避難所の集計統計
struct ShelterStats {
    let totalCount: Int
    let ageGroups: [AgeGroup: Int]
    let genders: [Gender: Int]
    /// "なし" / "軽傷" / "中程度" / "重傷" / "不明" などのカウント
    let injuries: [String: Int]
    let specialNeeds: [SpecialNeed: Int]
    /// cardType == .residenceCard の登録者数
    let foreignResidents: Int

    static let empty = ShelterStats(
        totalCount: 0,
        ageGroups: [:],
        genders: [:],
        injuries: [:],
        specialNeeds: [:],
        foreignResidents: 0
    )
}

/// 必要物資概算
///
/// 算出基準(内閣府「避難所における良好な生活環境の確保に向けた取組指針」準拠):
/// - 飲料水: 3 L/人/日
/// - 食料: 3 食/人/日
/// - 毛布: 1 枚/人(日数不問)
/// - おむつ: 乳幼児 × 5 枚/日
/// - 粉ミルク: 乳幼児 × 1 缶/日
/// - 生理用品: SpecialNeed.sanitary 登録者 × 1 パック/日
/// - 医薬品セット: 怪我ステータスが「なし」以外の人数(日数不問)
struct SupplyEstimate {
    let days: Int
    let water: Double      // L
    let meals: Int
    let blankets: Int
    let diapers: Int
    let formula: Int
    let sanitaryPads: Int
    let medicalKits: Int
}

// MARK: - ShelterAnalytics

enum ShelterAnalytics {

    /// 全レコードから ShelterStats を集計
    static func computeStats(from records: [EvacueeRecord]) -> ShelterStats {
        guard !records.isEmpty else { return .empty }

        var ageGroups: [AgeGroup: Int] = [:]
        var genders: [Gender: Int] = [:]
        var injuries: [String: Int] = [:]
        var specialNeeds: [SpecialNeed: Int] = [:]
        var foreignResidents = 0

        for r in records {
            ageGroups[r.ageGroup, default: 0] += 1
            genders[r.gender, default: 0] += 1
            injuries[r.injuryStatus, default: 0] += 1
            for need in r.specialNeeds {
                specialNeeds[need, default: 0] += 1
            }
        }
        // 外国人検出: cardType == .residenceCard に加え、名前ベース推定も包含(detectForeignResidents)
        foreignResidents = detectForeignResidents(records).count

        return ShelterStats(
            totalCount: records.count,
            ageGroups: ageGroups,
            genders: genders,
            injuries: injuries,
            specialNeeds: specialNeeds,
            foreignResidents: foreignResidents
        )
    }

    /// 必要物資を概算
    static func estimateSupplies(from stats: ShelterStats, days: Int) -> SupplyEstimate {
        let total = stats.totalCount
        let infants = stats.ageGroups[.infant] ?? 0
        let sanitaryUsers = stats.specialNeeds[.sanitary] ?? 0

        // 怪我「なし」「不明」「(空文字)」以外を負傷者扱い
        let injured = stats.injuries.reduce(0) { acc, kv in
            let key = kv.key
            if key == "なし" || key == "不明" || key.isEmpty {
                return acc
            }
            return acc + kv.value
        }

        return SupplyEstimate(
            days: days,
            water: Double(total) * 3.0 * Double(days),
            meals: total * 3 * days,
            blankets: total,
            diapers: infants * 5 * days,
            formula: infants * 1 * days,
            sanitaryPads: sanitaryUsers * 1 * days,
            medicalKits: injured
        )
    }

    // MARK: - AI Context

    /// AIアシスタント用の構造化コンテキスト文字列を生成
    ///
    /// Gemma 4 E2B (2B effective params) 向けに **理解しやすさを最優先**:
    /// - key:value形式ではなく自然言語の日本語文(E2Bは数値のkey:valueをパースしにくい)
    /// - 各セクションを `[見出し]` で明確に区切る(モデルが参照しやすい)
    /// - 0件のフィールドは「0名」と明記(「なし」と読み飛ばしを誘発しない)
    /// - 怪我人には怪我部位(injuryLocations)も含める
    /// - トークン効率は維持(E2Bのcontext_length 2048 を超えないこと)
    ///
    /// 例(18名時、約450トークン以内):
    /// ```
    /// [避難所概要]
    /// 避難者合計: 18名
    ///
    /// [年齢内訳]
    /// 乳幼児: 2名
    /// 子供: 2名
    /// 成人: 8名
    /// 高齢者: 5名
    ///
    /// [性別]
    /// 女性: 9名、男性: 8名
    ///
    /// [怪我人: 6名]
    /// 重傷: 鈴木武雄(高齢者,男性,頭部)
    /// 中程度: 佐藤由香(成人,女性,右脚)、渡辺翔(成人,男性,肩・左腕)
    /// 軽傷: 田中健一(成人,男性,右腕)、鈴木静子(高齢者,女性,左脚)、Wei Chen(成人,男性,右手)
    ///
    /// [配慮が必要な方]
    /// 車椅子利用者: 4名
    /// 乳幼児ケアが必要: 4名
    /// 生理用品が必要: 5名
    /// その他配慮: 3名
    ///
    /// [3日分必要物資]
    /// 水: 162L、食料: 162食、毛布: 18枚
    /// おむつ: 30枚、粉ミルク: 6缶、生理用品: 15パック、医薬品: 6セット
    /// ```
    static func generateContext(db: DatabaseService, days: Int = 3) -> String {
        let records = (try? db.fetchAll()) ?? []
        let stats = computeStats(from: records)

        if stats.totalCount == 0 {
            return "[避難所概要]\n避難者合計: 0名"
        }

        let supplies = estimateSupplies(from: stats, days: days)

        var lines: [String] = []

        // === 避難所概要 ===
        lines.append("[避難所概要]")
        lines.append("避難者合計: \(stats.totalCount)名")
        if stats.foreignResidents > 0 {
            lines.append("うち外国人住民: \(stats.foreignResidents)名")
        }
        lines.append("")

        // === 年齢内訳(全グループを必ず表示。0名でも明記してAIが拾えるように)===
        lines.append("[年齢内訳]")
        let ageOrder: [AgeGroup] = [.infant, .child, .adult, .elderly]
        for g in ageOrder {
            let n = stats.ageGroups[g] ?? 0
            lines.append("\(ageLabelShort(g)): \(n)名")
        }
        lines.append("")

        // === 性別 ===
        var genderParts: [String] = []
        let f = stats.genders[.female] ?? 0
        let m = stats.genders[.male] ?? 0
        let o = stats.genders[.other] ?? 0
        if f > 0 { genderParts.append("女性: \(f)名") }
        if m > 0 { genderParts.append("男性: \(m)名") }
        if o > 0 { genderParts.append("その他: \(o)名") }
        if !genderParts.isEmpty {
            lines.append("[性別]")
            lines.append(genderParts.joined(separator: "、"))
            lines.append("")
        }

        // === 怪我人リスト(重傷→中程度→軽傷の順、各人の部位も含む)===
        let injured = records.filter { $0.injuryStatus != "なし" && $0.injuryStatus != "不明" && !$0.injuryStatus.isEmpty }
        if !injured.isEmpty {
            lines.append("[怪我人: \(injured.count)名]")
            // 重症度別にグループ化
            let order: [(String, Int)] = [("重傷", 0), ("中程度", 1), ("軽傷", 2)]
            for (severity, _) in order {
                let group = injured.filter { simplifySeverity($0.injuryStatus) == severity }
                if group.isEmpty { continue }
                let entries = group.map { r -> String in
                    let parts = r.injuryLocations.isEmpty
                        ? "\(r.ageGroup.label),\(r.gender.label)"
                        : "\(r.ageGroup.label),\(r.gender.label),\(r.injuryLocations.joined(separator: "・"))"
                    return "\(r.name)(\(parts))"
                }
                lines.append("\(severity): \(entries.joined(separator: "、"))")
            }
            lines.append("")
        }

        // === 配慮が必要な方(年齢グループ+specialNeedsを統合。E2Bがセクション間を跨げないため)===
        lines.append("[配慮が必要な方]")
        // 年齢ベースの要配慮者(乳幼児・高齢者)
        let infants = stats.ageGroups[.infant] ?? 0
        let elderly = stats.ageGroups[.elderly] ?? 0
        lines.append("乳幼児: \(infants)名")
        lines.append("高齢者: \(elderly)名")
        // specialNeedsベースの要配慮者
        let needsOrder: [SpecialNeed] = [.wheelchair, .infantCare, .sanitary, .other]
        for n in needsOrder {
            let c = stats.specialNeeds[n] ?? 0
            lines.append("\(specialNeedLabelLong(n)): \(c)名")
        }
        lines.append("")

        // === 必要物資(自然言語で)===
        lines.append("[\(supplies.days)日分必要物資]")
        let basicSupplies = "水: \(Int(supplies.water))L、食料: \(supplies.meals)食、毛布: \(supplies.blankets)枚"
        lines.append(basicSupplies)
        var extraSupplies: [String] = []
        if supplies.diapers > 0 { extraSupplies.append("おむつ: \(supplies.diapers)枚") }
        if supplies.formula > 0 { extraSupplies.append("粉ミルク: \(supplies.formula)缶") }
        if supplies.sanitaryPads > 0 { extraSupplies.append("生理用品: \(supplies.sanitaryPads)パック") }
        if supplies.medicalKits > 0 { extraSupplies.append("医薬品: \(supplies.medicalKits)セット") }
        if !extraSupplies.isEmpty {
            lines.append(extraSupplies.joined(separator: "、"))
        }

        // 末尾の空行を削除
        while lines.last == "" { lines.removeLast() }

        return lines.joined(separator: "\n")
    }

    // MARK: - Deterministic Preset Answers
    //
    // E2B (2Bパラメータ) は「セクションを跨いだ数値抽出」「似たラベルの混同回避」が苦手。
    // 配慮事項・怪我人・物資のような **データ確定型** の質問は、AIに通すと精度が落ちる。
    // よって、プリセット質問の回答は ShelterAnalytics 側で確定テキストを生成し、
    // AIアシスタント画面ではそれを直接表示する(精度100%、生成も即時)。
    //
    // 自由入力の質問のみ、generateContext + Gemma を使用する。

    /// プリセット質問の種別
    enum PresetKind {
        case injuryStatus       // 怪我人の状況
        case supplies           // 必要物資
        case specialNeeds       // 要配慮者
        case overallSummary     // 全体サマリー
        case foreignSupport     // 外国人対応
    }

    /// プリセット質問に対する確定回答を生成
    /// AIモデルを使わず、登録データから直接フォーマットするため精度100%。
    static func generatePresetAnswer(_ kind: PresetKind, db: DatabaseService) -> String {
        let records = (try? db.fetchAll()) ?? []
        if records.isEmpty {
            return "避難者がまだ登録されていません。"
        }
        let stats = computeStats(from: records)

        switch kind {
        case .injuryStatus:
            return injuryStatusReport(records: records)
        case .supplies:
            return suppliesReport(stats: stats, days: 3)
        case .specialNeeds:
            return specialNeedsReport(records: records, stats: stats)
        case .overallSummary:
            return overallSummaryReport(records: records, stats: stats)
        case .foreignSupport:
            return foreignSupportReport(records: records)
        }
    }

    // MARK: - Preset: 怪我人の状況

    private static func injuryStatusReport(records: [EvacueeRecord]) -> String {
        let injured = records.filter {
            $0.injuryStatus != "なし"
            && $0.injuryStatus != "不明"
            && !$0.injuryStatus.isEmpty
        }
        if injured.isEmpty {
            return "■怪我人数: 0名\n現在、怪我の登録はありません。"
        }

        var lines: [String] = []
        lines.append("■怪我人数: \(injured.count)名")
        lines.append("")
        lines.append("■重症度別")

        let order: [String] = ["重傷", "中程度", "軽傷"]
        for severity in order {
            let group = injured.filter { simplifySeverity($0.injuryStatus) == severity }
            if group.isEmpty { continue }
            lines.append("〔\(severity): \(group.count)名〕")
            for r in group {
                let parts = r.injuryLocations.isEmpty ? r.injuryStatus : r.injuryLocations.joined(separator: "・")
                lines.append("・\(r.name)(\(r.ageGroup.label)/\(r.gender.label)): \(parts)")
            }
        }

        lines.append("")
        lines.append("■対応優先度")
        let prioritized = injured.sorted { a, b in
            let order: [String: Int] = ["重傷": 0, "中程度": 1, "軽傷": 2]
            return (order[simplifySeverity(a.injuryStatus)] ?? 99) < (order[simplifySeverity(b.injuryStatus)] ?? 99)
        }
        let names = prioritized.map { "\($0.name)(\(simplifySeverity($0.injuryStatus)))" }
        lines.append(names.joined(separator: " → "))

        return lines.joined(separator: "\n")
    }

    // MARK: - Preset: 必要物資

    private static func suppliesReport(stats: ShelterStats, days: Int) -> String {
        let s = estimateSupplies(from: stats, days: days)
        var lines: [String] = []
        lines.append("■\(s.days)日分の必要物資(\(stats.totalCount)名分)")
        lines.append("")
        lines.append("〔基本物資〕")
        lines.append("・飲料水: \(Int(s.water))L (1人3L×\(days)日)")
        lines.append("・食料: \(s.meals)食 (1人3食×\(days)日)")
        lines.append("・毛布: \(s.blankets)枚 (1人1枚)")

        var extras: [String] = []
        if s.diapers > 0 { extras.append("・おむつ: \(s.diapers)枚") }
        if s.formula > 0 { extras.append("・粉ミルク: \(s.formula)缶") }
        if s.sanitaryPads > 0 { extras.append("・生理用品: \(s.sanitaryPads)パック") }
        if s.medicalKits > 0 { extras.append("・医薬品: \(s.medicalKits)セット") }
        if !extras.isEmpty {
            lines.append("")
            lines.append("〔配慮物資〕")
            lines.append(contentsOf: extras)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Preset: 要配慮者

    private static func specialNeedsReport(records: [EvacueeRecord], stats: ShelterStats) -> String {
        let infants = stats.ageGroups[.infant] ?? 0
        let elderly = stats.ageGroups[.elderly] ?? 0
        let wheelchair = stats.specialNeeds[.wheelchair] ?? 0
        let infantCare = stats.specialNeeds[.infantCare] ?? 0
        let sanitary = stats.specialNeeds[.sanitary] ?? 0
        let other = stats.specialNeeds[.other] ?? 0

        var lines: [String] = []
        lines.append("■乳幼児: \(infants)名")
        if infants > 0 {
            let names = records.filter { $0.ageGroup == .infant }.map { $0.name }
            lines.append("  \(names.joined(separator: "、"))")
        }

        lines.append("■高齢者: \(elderly)名")
        if elderly > 0 {
            let names = records.filter { $0.ageGroup == .elderly }.map { $0.name }
            lines.append("  \(names.joined(separator: "、"))")
        }

        lines.append("■車椅子: \(wheelchair)名")
        if wheelchair > 0 {
            let names = records.filter { $0.specialNeeds.contains(.wheelchair) }.map { $0.name }
            lines.append("  \(names.joined(separator: "、"))")
        }

        lines.append("")
        lines.append("■その他必要な対応")
        if infantCare > 0 { lines.append("・おむつ・ミルク対応: \(infantCare)名") }
        if sanitary > 0 { lines.append("・生理用品配布: \(sanitary)名") }
        if other > 0 { lines.append("・その他配慮: \(other)名") }
        if infantCare == 0 && sanitary == 0 && other == 0 {
            lines.append("・特記事項なし")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Preset: 全体サマリー

    private static func overallSummaryReport(records: [EvacueeRecord], stats: ShelterStats) -> String {
        let infants = stats.ageGroups[.infant] ?? 0
        let children = stats.ageGroups[.child] ?? 0
        let adults = stats.ageGroups[.adult] ?? 0
        let elderly = stats.ageGroups[.elderly] ?? 0

        let injured = records.filter {
            $0.injuryStatus != "なし"
            && $0.injuryStatus != "不明"
            && !$0.injuryStatus.isEmpty
        }
        let severe = injured.filter { simplifySeverity($0.injuryStatus) == "重傷" }.count
        let moderate = injured.filter { simplifySeverity($0.injuryStatus) == "中程度" }.count
        let mild = injured.filter { simplifySeverity($0.injuryStatus) == "軽傷" }.count

        let supplies = estimateSupplies(from: stats, days: 3)

        var lines: [String] = []
        lines.append("■避難者総数: \(stats.totalCount)名")
        var ageBreakdown: [String] = []
        if infants > 0 { ageBreakdown.append("乳幼児\(infants)") }
        if children > 0 { ageBreakdown.append("子供\(children)") }
        if adults > 0 { ageBreakdown.append("成人\(adults)") }
        if elderly > 0 { ageBreakdown.append("高齢者\(elderly)") }
        lines.append("  内訳: \(ageBreakdown.joined(separator: "、"))")

        lines.append("")
        lines.append("■怪我人状況: 計\(injured.count)名")
        var injuryParts: [String] = []
        if severe > 0 { injuryParts.append("重傷\(severe)") }
        if moderate > 0 { injuryParts.append("中程度\(moderate)") }
        if mild > 0 { injuryParts.append("軽傷\(mild)") }
        if injuryParts.isEmpty {
            lines.append("  怪我人なし")
        } else {
            lines.append("  内訳: \(injuryParts.joined(separator: "、"))")
        }

        lines.append("")
        lines.append("■物資状況(3日分)")
        lines.append("  水\(Int(supplies.water))L、食料\(supplies.meals)食、毛布\(supplies.blankets)枚")

        return lines.joined(separator: "\n")
    }

    // MARK: - Preset: 外国人対応

    /// 外国人住民を検出。cardTypeが.residenceCardの登録者に加え、
    /// 名前が日本語以外(カタカナ・英字)の登録者も外国人と推定する。
    /// サンプルデータでは cardType=.other になっているため、名前ベース推定が必須。
    static func detectForeignResidents(_ records: [EvacueeRecord]) -> [EvacueeRecord] {
        return records.filter { isForeignResident($0) }
    }

    /// 名前ベースの外国人推定。
    /// - cardType=.residenceCard なら確定で外国人
    /// - 名前に1つでも漢字/ひらがなが含まれない場合(英字 or カタカナのみ)は外国人と推定
    ///   ただし「カタカナのみの日本人名」(例: ヤマダ) と区別するため、英字含有を優先判定。
    private static func isForeignResident(_ r: EvacueeRecord) -> Bool {
        if r.cardType == CardType.residenceCard.rawValue { return true }

        let name = r.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return false }

        // 英字を1文字でも含めば外国人
        let hasLatin = name.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.isASCII }
        if hasLatin { return true }

        // 漢字・ひらがなを1文字も含まず、カタカナのみ → 外国人推定
        // (姓または名が漢字を含めば日本人としてみなす)
        let kanjiHiraganaSet = CharacterSet(charactersIn: "\u{3040}\u{309F}")  // ひらがな
            .union(.init(charactersIn: "\u{4E00}\u{9FFF}"))                  // 漢字
        let hasJapanese = name.unicodeScalars.contains { kanjiHiraganaSet.contains($0) }
        if hasJapanese { return false }

        // カタカナを含むがひらがな・漢字を含まない
        let katakanaSet = CharacterSet(charactersIn: "\u{30A0}\u{30FF}")
        let hasKatakana = name.unicodeScalars.contains { katakanaSet.contains($0) }
        return hasKatakana
    }

    private static func foreignSupportReport(records: [EvacueeRecord]) -> String {
        let foreigners = detectForeignResidents(records)
        if foreigners.isEmpty {
            return "外国人避難者の登録はありません。"
        }

        var lines: [String] = []
        lines.append("■人数: \(foreigners.count)名")
        lines.append("")
        lines.append("■登録者")
        for r in foreigners {
            let injuryNote: String
            if r.injuryStatus != "なし" && r.injuryStatus != "不明" && !r.injuryStatus.isEmpty {
                injuryNote = " / \(simplifySeverity(r.injuryStatus))"
            } else {
                injuryNote = ""
            }
            lines.append("・\(r.name)(\(r.ageGroup.label)/\(r.gender.label))\(injuryNote)")
        }

        lines.append("")
        lines.append("■必要な対応")
        lines.append("・多言語対応の案内表示(英語・中国語等)")
        lines.append("・通訳ボランティアまたは翻訳アプリの手配")
        lines.append("・在留カード/パスポート確認による身元把握")
        let injuredForeigners = foreigners.filter {
            $0.injuryStatus != "なし" && $0.injuryStatus != "不明" && !$0.injuryStatus.isEmpty
        }
        if !injuredForeigners.isEmpty {
            lines.append("・医療対応時の言語サポート(\(injuredForeigners.count)名が要医療)")
        }
        lines.append("・大使館・領事館への連絡経路確保")

        return lines.joined(separator: "\n")
    }

    /// 怪我ステータスから重症度を抽出(「軽傷(右腕擦り傷)」→「軽傷」など)
    private static func simplifySeverity(_ status: String) -> String {
        if status.hasPrefix("重傷") { return "重傷" }
        if status.hasPrefix("中程度") { return "中程度" }
        if status.hasPrefix("軽傷") { return "軽傷" }
        return status
    }

    // MARK: - Helpers

    private static func ageLabelShort(_ g: AgeGroup) -> String {
        switch g {
        case .infant: return "乳幼児"
        case .child: return "子供"
        case .adult: return "成人"
        case .elderly: return "高齢者"
        }
    }

    /// AIコンテキスト用の自然言語ラベル(E2Bが「車椅子:3」より「車椅子利用者: 3名」の方を理解しやすい)
    private static func specialNeedLabelLong(_ n: SpecialNeed) -> String {
        switch n {
        case .sanitary: return "生理用品が必要"
        case .infantCare: return "おむつ・ミルク対応が必要"
        case .wheelchair: return "車椅子利用者"
        case .other: return "その他配慮"
        }
    }
}

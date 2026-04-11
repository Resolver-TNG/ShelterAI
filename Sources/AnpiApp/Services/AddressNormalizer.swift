import Foundation

/// 住所文字列から「丁目レベル」の正規化文字列を抽出する
struct AddressNormalizer {

    /// 都道府県47件（境界マッチに使用）
    private static let prefectures: [String] = [
        "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
        "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
        "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県",
        "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県",
        "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県",
        "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県",
        "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"
    ]

    /// 住所を丁目レベルまで正規化する
    ///
    /// 例:
    /// - "東京都渋谷区恵比寿1丁目3番5号" → "東京都渋谷区恵比寿1丁目"
    /// - "渋谷区恵比寿1-3-5"           → "渋谷区恵比寿1"
    /// - "札幌市中央区北1条西2丁目"    → "札幌市中央区北1条西2丁目"
    /// - "札幌市中央区北1条西2-3-4"    → "札幌市中央区北1条西2"
    static func normalize(_ address: String) -> String {
        // 1. 全角数字→半角、全角ハイフン類を統一
        var normalized = address.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? address
        normalized = normalized
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "ー", with: "-")
            .replacingOccurrences(of: "−", with: "-")

        // 2. 北海道方式の「N条西M丁目」「N条東M丁目」→ そのまま末尾の「M丁目」までで切る
        //    （「条」だけでは住所が完結しないので「丁目」もしくは数字+ハイフンまで含める）
        if let range = normalized.range(
            of: #"\d+条[東西南北]?\d+丁目"#,
            options: .regularExpression
        ) {
            return String(normalized[..<range.upperBound])
        }

        // 3. 一般的な「〇丁目」パターン
        if let range = normalized.range(of: #"\d+丁目"#, options: .regularExpression) {
            return String(normalized[..<range.upperBound])
        }

        // 4. 北海道方式の「N条西M-X-Y」: N条西/東/南/北Mまで
        if let range = normalized.range(
            of: #"\d+条[東西南北]?\d+(?=[-\s])"#,
            options: .regularExpression
        ) {
            return String(normalized[..<range.upperBound])
        }

        // 5. 「〇-」パターン（ハイフン区切り住所）: 最初の数字ブロックまで
        if let range = normalized.range(of: #"[^\d]\d+-"#, options: .regularExpression) {
            // ハイフンの手前まで
            let end = normalized.index(range.upperBound, offsetBy: -1)
            return String(normalized[..<end])
        }

        // 6. フォールバック: 都道府県+市区町村+町域までを保持
        //    都道府県 → 「市」「区」「町」「村」のいずれかが現れる位置の次まで
        return fallbackTrim(normalized)
    }

    /// 都道府県+市区町村+町域までを推定して切り出すフォールバック
    /// 例: "東京都渋谷区恵比寿西1234"（丁目もハイフンも無い）→ "東京都渋谷区恵比寿西"
    private static func fallbackTrim(_ s: String) -> String {
        // 数字が出る直前まで保持（住所末尾の番地っぽい数字を切り落とす）
        if let range = s.range(of: #"\d"#, options: .regularExpression) {
            let trimmed = String(s[..<range.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        // 数字が無い → 全文（ただし長すぎる場合は40文字でカット）
        if s.count > 40 {
            return String(s.prefix(40))
        }
        return s
    }

    /// 名前から姓を抽出する（スペース/全角スペース区切り）
    static func extractFamilyName(_ fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespaces)
        // 空白（半角・全角）で分割
        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: " \u{3000}"))
            .filter { !$0.isEmpty }
        return parts.first ?? trimmed
    }
}

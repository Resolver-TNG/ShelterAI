import Foundation

// MARK: - CardType

enum CardType: String, CaseIterable, Codable {
    case mynumber       = "マイナンバーカード"
    case driverLicense  = "運転免許証"
    case passport       = "パスポート"
    case residenceCard  = "在留カード"
    case healthInsurance = "健康保険証"
    case other          = "その他"

    var icon: String {
        switch self {
        case .mynumber:        return "🪪"
        case .driverLicense:   return "🚗"
        case .passport:        return "✈️"
        case .residenceCard:   return "🌏"
        case .healthInsurance: return "💊"
        case .other:           return "📄"
        }
    }
}

// MARK: - CardAnalysisResult

struct CardAnalysisResult {
    var cardType: CardType
    var name: String
    var address: String
    var dateOfBirth: String     // "YYYY年MM月DD日" 形式
    var confidence: Float       // 0.0〜1.0
    var rawResponse: String     // Gemmaの生レスポンス（デバッグ用）

    /// Vision OCR (CardOCRService) の結果から変換
    static func fromOCR(name: String, address: String, dateOfBirth: String) -> CardAnalysisResult {
        CardAnalysisResult(
            cardType: .other,
            name: name,
            address: address,
            dateOfBirth: dateOfBirth,
            confidence: 0.6,
            rawResponse: "(Vision OCR fallback)"
        )
    }

    /// 確信度が低いか判定（0.7未満 → 再撮影を促す）
    var isLowConfidence: Bool { confidence < 0.7 }
}

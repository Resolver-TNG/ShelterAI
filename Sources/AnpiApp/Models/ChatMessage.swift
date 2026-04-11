import Foundation

/// AIアシスタント会話の1メッセージ
///
/// `text` を `var` にしているのはストリーミング応答中に
/// `assistant` メッセージのテキストを逐次更新するため。
struct ChatMessage: Identifiable, Equatable {
    let id: UUID = UUID()
    let role: Role
    var text: String
    let timestamp: Date

    enum Role: String {
        case user
        case assistant
        case system   // コンテキスト注入用（UI非表示）
    }

    init(role: Role, text: String, timestamp: Date = Date()) {
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

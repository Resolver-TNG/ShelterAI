import SwiftUI

/// モード選択画面に戻るための通知名
///
/// `MainTabView` 配下の任意のViewから `NotificationCenter.default.post(...)` で発火し、
/// `LaunchModeView` が `onReceive` で受信して `selectedMode = nil` にリセットする。
/// 各タブが独立した `NavigationStack` を持つ構造のため、
/// props drilling を避けてグローバル通知で扱う。
extension Notification.Name {
    static let exitToModeSelection = Notification.Name("anpiapp.exitToModeSelection")
}

/// 各タブのtoolbar leadingに配置する「モード選択に戻る」ボタン
///
/// confirmationDialog で確認してから `.exitToModeSelection` を post する。
/// 登録データはモード切替時に削除されない（テストモードのデータ削除は専用ボタンで対応）。
struct ExitToModeSelectionButton: View {
    @State private var showConfirmation = false

    var body: some View {
        Button {
            showConfirmation = true
        } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
        }
        .accessibilityLabel("モード選択に戻る")
        .confirmationDialog(
            "モード選択に戻りますか？",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("戻る") {
                NotificationCenter.default.post(name: .exitToModeSelection, object: nil)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("登録データは保持されます。")
        }
    }
}

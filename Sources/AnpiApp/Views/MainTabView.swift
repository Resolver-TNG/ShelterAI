import SwiftUI

/// メインタブUI
///
/// `LaunchModeView` から直接表示される（外側の `NavigationStack` は持たない）。
/// 各タブが独自の `NavigationStack` を持つ単純な構造に変更し、
/// 二重ネストによるエッジスワイプ・戻るジェスチャー誤動作を防止する。
struct MainTabView: View {
    let isEmergencyMode: Bool
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 0: 記録
            NavigationStack {
                RegistrationHomeView(isEmergencyMode: isEmergencyMode)
            }
            .tabItem {
                Label("記録", systemImage: "list.clipboard")
            }
            .tag(0)

            // Tab 1: 状況
            NavigationStack {
                SituationView()
            }
            .tabItem {
                Label("状況", systemImage: "chart.bar.fill")
            }
            .tag(1)

            // Tab 2: AI
            NavigationStack {
                AIAssistantView()
            }
            .tabItem {
                Label("AI", systemImage: "brain.head.profile")
            }
            .tag(2)
        }
    }
}

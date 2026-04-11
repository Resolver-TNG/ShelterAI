import SwiftUI

/// アプリ起動時のモード選択画面
///
/// 「緊急事態モード」または「テスト起動」を選んで `MainTabView` に切り替える。
/// `NavigationStack` + `navigationDestination` による遷移は使わず、
/// `selectedMode` enum を切り替えて直接 `MainTabView` を表示する。
/// これにより外側の `NavigationStack` が `MainTabView` 内のジェスチャー/遷移と
/// 二重化することを避け、エッジスワイプ等で起動画面に戻るバグを防ぐ。
struct LaunchModeView: View {
    @EnvironmentObject var db: DatabaseService
    @EnvironmentObject var location: LocationService

    /// 起動モード（nil の間は選択画面を表示）
    private enum LaunchMode {
        case emergency
        case test
    }

    @State private var selectedMode: LaunchMode? = nil
    @State private var totalCount = 0

    var body: some View {
        if let mode = selectedMode {
            // モード選択後は MainTabView を直接表示（NavigationStack を被せない）
            MainTabView(isEmergencyMode: mode == .emergency)
                .onReceive(NotificationCenter.default.publisher(for: .exitToModeSelection)) { _ in
                    selectedMode = nil
                }
        } else {
            modeSelectionView
        }
    }

    // MARK: - モード選択画面

    private var modeSelectionView: some View {
        VStack(spacing: 0) {
            // ヘッダー
            VStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("避難所管理 ShelterAI")
                    .font(.largeTitle).bold()
                Text("Powered by Gemma 4 — 完全オフライン")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 32)

            Divider()

            VStack(spacing: 16) {
                // 登録件数バッジ（情報表示のみ）
                if totalCount > 0 {
                    HStack {
                        Image(systemName: "person.3.fill")
                        Text("登録済み: \(totalCount)件")
                            .font(.subheadline).bold()
                        Spacer()
                    }
                    .padding()
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // 緊急事態モード
                Button {
                    location.requestPermission()
                    location.start()
                    selectedMode = .emergency
                } label: {
                    VStack(spacing: 6) {
                        Label("緊急事態モード", systemImage: "exclamationmark.triangle.fill")
                            .font(.title3).bold()
                        Text("データは永続保存されます")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .padding(.horizontal)

                // テストモード
                Button {
                    selectedMode = .test
                } label: {
                    VStack(spacing: 6) {
                        Label("テスト起動", systemImage: "wrench.fill")
                            .font(.title3)
                        Text("アプリ終了時にデータを自動削除します")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.borderedProminent).tint(.gray)
                .padding(.horizontal)
            }
            .padding(.top, 24)

            Spacer()
        }
        .onAppear {
            totalCount = (try? db.fetchAll().count) ?? 0
        }
    }
}

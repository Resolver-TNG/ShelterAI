import SwiftUI

/// 初回モデルセットアップUI（Issue #10）
/// Issue #26の方針: App Bundle内蔵が実現した場合は不要になるが、
/// DL方式でのデモ・開発中は使用する
struct ModelSetupView: View {
    @EnvironmentObject var modelManager: ModelManager
    let onComplete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // アイコン
            VStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                Text("AI機能のセットアップ")
                    .font(.title2).bold()
                Text("Gemma 4 AIモデル（約2.7GB）をダウンロードします。\nWi-Fi接続を推奨します。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // ステータス表示
            switch modelManager.modelStatus {
            case .notDownloaded:
                VStack(spacing: 16) {
                    Button {
                        Task { try? await modelManager.downloadModels() }
                    } label: {
                        Label("モデルをダウンロード", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("後で設定する（Vision OCRで起動）") {
                        onSkip()
                    }
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                }

            case .downloading(let progress):
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("\(Int(progress * 100))% ダウンロード中...")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("アプリを閉じないでください")
                        .font(.caption).foregroundStyle(.orange)
                }

            case .ready:
                VStack(spacing: 16) {
                    Label("モデルの準備完了", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                    Button("開始する") { onComplete() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .onAppear { onComplete() }

            case .error(let msg):
                VStack(spacing: 12) {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    Button("再試行") {
                        Task { try? await modelManager.downloadModels() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Vision OCRで起動") { onSkip() }
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("モデルは端末内にのみ保存されます。\n個人情報が外部に送信されることはありません。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)
        }
        .padding(32)
        .navigationTitle("AIセットアップ")
    }
}

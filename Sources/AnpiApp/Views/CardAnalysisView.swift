import SwiftUI

/// Gemma 4 解析中View — プログレス表示付き
struct CardAnalysisView: View {
    let cardImage: UIImage
    let onComplete: (CardAnalysisResult) -> Void
    let onFallback: () -> Void

    @EnvironmentObject var gemma: GemmaService
    @State private var errorMessage: String?
    @State private var analysisStarted = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 32) {
                // カードプレビュー
                Image(uiImage: cardImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    )

                if let errorMessage {
                    // エラー表示
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                        HStack(spacing: 16) {
                            Button("Vision OCRで試す") { onFallback() }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(.gray.opacity(0.7), in: Capsule())
                            Button("手動入力") { onFallback() }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(.blue.opacity(0.7), in: Capsule())
                        }
                    }
                } else {
                    // プログレス表示（GemmaServiceの@Publishedを直接参照）
                    VStack(spacing: 20) {
                        // %表示
                        Text("\(gemma.progressPercent)%")
                            .foregroundStyle(.white)
                            .font(.system(size: 48, weight: .bold, design: .monospaced))

                        // プログレスバー
                        ProgressView(value: Double(gemma.progressPercent), total: 100)
                            .progressViewStyle(.linear)
                            .tint(.green)
                            .frame(maxWidth: 250)

                        // ステップ名
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                            Text(gemma.progressStep.isEmpty ? "解析準備中..." : gemma.progressStep)
                                .foregroundStyle(.white)
                                .font(.subheadline)
                        }

                        Text("身分証の情報を読み取っています")
                            .foregroundStyle(.white.opacity(0.5))
                            .font(.caption)
                    }
                }
            }
            .padding(32)
        }
        .task {
            guard !analysisStarted else { return }
            analysisStarted = true
            await analyze()
        }
    }

    private func analyze() async {
        do {
            let result = try await gemma.analyzeCard(image: cardImage)
            await MainActor.run { onComplete(result) }
        } catch {
            await MainActor.run {
                errorMessage = "解析に失敗しました。\nVision OCRまたは手動入力に切り替えできます。"
            }
        }
    }
}

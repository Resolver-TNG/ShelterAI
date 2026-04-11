import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 1. このアプリについて
                    HelpSection(title: "このアプリについて", systemImage: "shield.checkered") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ShelterAI は iPhone 1台で避難所の受付業務を効率化する AI アシスタントアプリです。")
                            Text("身分証をカメラで撮影するだけで、AI が氏名・住所・生年月日を自動的に読み取り、登録作業を大幅に短縮します。")
                        }
                        .font(.body)
                        .foregroundStyle(.primary)
                    }

                    HelpDivider()

                    // 2. 使い方
                    HelpSection(title: "使い方", systemImage: "list.number") {
                        VStack(alignment: .leading, spacing: 12) {
                            HelpStep(number: 1, icon: "camera.fill", text: "カメラで身分証を撮影")
                            HelpStep(number: 2, icon: "cpu", text: "AI が氏名・住所・生年月日を自動読み取り")
                            HelpStep(number: 3, icon: "checkmark.circle.fill", text: "内容を確認して「登録」")
                        }
                    }

                    HelpDivider()

                    // 3. 対応カード
                    HelpSection(title: "対応カード", systemImage: "creditcard.and.123") {
                        VStack(alignment: .leading, spacing: 8) {
                            HelpCardRow(icon: "person.text.rectangle", text: "マイナンバーカード")
                            HelpCardRow(icon: "car.fill", text: "運転免許証")
                            HelpCardRow(icon: "airplane", text: "パスポート")
                            HelpCardRow(icon: "globe.asia.australia", text: "在留カード")
                            HelpCardRow(icon: "heart.text.clipboard", text: "健康保険証")
                        }
                    }

                    HelpDivider()

                    // 4. AI機能について
                    HelpSection(title: "AI 機能について", systemImage: "brain.head.profile") {
                        VStack(alignment: .leading, spacing: 8) {
                            HelpInfoRow(icon: "iphone", color: .blue, text: "Gemma 4 がデバイス上で動作")
                            HelpInfoRow(icon: "wifi.slash", color: .orange, text: "完全オフライン — インターネット不要")
                            HelpInfoRow(icon: "lock.shield.fill", color: .green, text: "個人情報は端末の外に出ない")
                        }
                        .padding(.top, 2)
                    }

                    HelpDivider()

                    // 5. 困ったら
                    HelpSection(title: "困ったら", systemImage: "questionmark.bubble") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("読み取れない場合は、結果確認画面で「手動入力に切り替え」をタップしてください。")
                            Text("AI での読み取りに失敗した場合も、Apple の文字認識（OCR）が自動的にバックアップとして動作します。")
                        }
                        .font(.body)
                        .foregroundStyle(.primary)
                    }

                    HelpDivider()

                    // 6. バージョン情報
                    HelpSection(title: "バージョン情報", systemImage: "info.circle") {
                        VStack(alignment: .leading, spacing: 6) {
                            HelpMetaRow(label: "アプリ", value: "ShelterAI v1.0")
                            HelpMetaRow(label: "コンペ", value: "Gemma 4 Good Hackathon 2026")
                            HelpMetaRow(label: "ライセンス", value: "Apache License 2.0")
                        }
                    }

                    Spacer(minLength: 32)
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("ヘルプ")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Helper Views

private struct HelpSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct HelpDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 20)
    }
}

private struct HelpStep: View {
    let number: Int
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.body)
        }
    }
}

private struct HelpCardRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.body)
        }
    }
}

private struct HelpInfoRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.body)
        }
    }
}

private struct HelpMetaRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    HelpView()
}

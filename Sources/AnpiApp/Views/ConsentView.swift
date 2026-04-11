import SwiftUI

/// NFC読み取り前の本人同意確認画面
struct ConsentView: View {
    let onConsent: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("本人確認のお願い")
                .font(.title2).bold()

            Text("緊急事態のため、本人確認のために以下の情報を記録します。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("氏名・生年月日・住所", systemImage: "person.text.rectangle")
                Label("記録日時・場所（GPS）", systemImage: "location")
                Label("写真（怪我状況）", systemImage: "camera")
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            Text("データは本端末にのみ保存され、外部には送信されません。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("同意して登録に進む") { onConsent() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

            Button("キャンセル", role: .cancel) { onCancel() }
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

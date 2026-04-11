import SwiftUI

/// OCR / Gemma 4 読み取り結果の確認・修正画面（Issue #13）
struct CardScanResultView: View {
    @Binding var name: String
    @Binding var address: String
    @Binding var dateOfBirthText: String
    var cardType: CardType = .other
    var confidence: Float = 0.0

    let onConfirm: () -> Void
    let onRetry: () -> Void

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("カード情報を読み取りました")
                            .font(.subheadline)
                        HStack(spacing: 6) {
                            Text(cardType.icon + " " + cardType.rawValue)
                                .font(.caption).foregroundStyle(.secondary)
                            if confidence > 0 {
                                Text("確信度 \(Int(confidence * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(confidence < 0.7 ? .orange : .secondary)
                            }
                        }
                    }
                    Spacer()
                    Button("撮り直す") { onRetry() }
                        .font(.caption).foregroundStyle(.blue)
                }

                if confidence < 0.7 && confidence > 0 {
                    Label("確信度が低めです。内容を確認してください。", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("確認・修正してください") {
                HStack {
                    Text("氏名").frame(width: 80, alignment: .leading).foregroundStyle(.secondary)
                    TextField("氏名", text: $name)
                }
                HStack {
                    Text("住所").frame(width: 80, alignment: .leading).foregroundStyle(.secondary)
                    TextField("住所", text: $address)
                }
                HStack {
                    Text("生年月日").frame(width: 80, alignment: .leading).foregroundStyle(.secondary)
                    TextField("例: 1990年01月01日", text: $dateOfBirthText)
                        .keyboardType(.numbersAndPunctuation)
                }
            }

            Section {
                let emptyFields = [name.isEmpty ? "氏名" : nil, address.isEmpty ? "住所" : nil].compactMap { $0 }
                if !emptyFields.isEmpty {
                    Label("未入力: \(emptyFields.joined(separator: "、"))", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section {
                Button("この内容で登録する") { onConfirm() }
                    .disabled(name.isEmpty)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("読み取り結果の確認")
    }
}

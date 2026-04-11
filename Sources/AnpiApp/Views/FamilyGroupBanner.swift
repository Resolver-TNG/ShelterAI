import SwiftUI

struct FamilyGroupBanner: View {
    let candidates: [EvacueeRecord]
    let onJoin: (EvacueeRecord) -> Void
    let onSeparate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("家族グループの候補が見つかりました", systemImage: "person.2.fill")
                .font(.subheadline).bold()
                .foregroundStyle(.blue)

            ForEach(candidates) { candidate in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.name)
                            .font(.subheadline)
                        Text(candidate.address)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("同じ家族") {
                        onJoin(candidate)
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.caption)
                    .tint(.blue)
                }
                .padding(.vertical, 4)

                if candidate.id != candidates.last?.id {
                    Divider()
                }
            }

            Button("別の家族として登録") {
                onSeparate()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

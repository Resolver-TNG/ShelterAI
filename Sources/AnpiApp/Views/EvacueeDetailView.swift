import SwiftUI

struct EvacueeDetailView: View {
    let record: EvacueeRecord
    @EnvironmentObject var db: DatabaseService
    @Environment(\.dismiss) private var dismiss

    @State private var injuryStatus: String
    @State private var selectedNeeds: Set<SpecialNeed>
    @State private var showSaved = false
    @State private var showDeleteConfirm = false

    init(record: EvacueeRecord) {
        self.record = record
        _injuryStatus = State(initialValue: record.injuryStatus)
        _selectedNeeds = State(initialValue: Set(record.specialNeeds))
    }

    private let injuryOptions = ["なし", "軽傷", "中程度", "重傷", "不明"]

    var body: some View {
        Form {
            Section("基本情報") {
                labelRow("氏名", record.name)
                labelRow("住所", record.address.isEmpty ? "未登録" : record.address)
                labelRow("生年月日", formatDate(record.dateOfBirth))
                labelRow("性別", record.gender.label)
                labelRow("年齢グループ", record.ageGroup.label)
            }

            Section("怪我状況（編集可）") {
                Picker("状況", selection: $injuryStatus) {
                    ForEach(injuryOptions, id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)

                if !record.injuryLocations.isEmpty {
                    HStack(alignment: .top) {
                        Text("部位").foregroundStyle(.secondary)
                        Spacer()
                        Text(record.injuryLocations.joined(separator: "、"))
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("配慮事項（編集可）") {
                ForEach(SpecialNeed.allCases, id: \.self) { need in
                    Toggle(need.label, isOn: Binding(
                        get: { selectedNeeds.contains(need) },
                        set: { on in
                            if on { selectedNeeds.insert(need) }
                            else { selectedNeeds.remove(need) }
                        }
                    ))
                }
            }

            if let gid = record.familyGroupId {
                Section("家族グループ") {
                    labelRow("グループID", String(gid.prefix(8)) + "...")
                    FamilyMembersSection(familyGroupId: gid, currentId: record.id)
                }
            }

            Section("登録情報") {
                if let lat = record.latitude, let lon = record.longitude {
                    labelRow("GPS", String(format: "%.4f, %.4f", lat, lon))
                }
                labelRow("モード", record.isEmergencyMode ? "🚨 緊急事態" : "🔧 テスト")
                labelRow("登録日時", formatDateTime(record.createdAt))
            }

            Section {
                Button("保存する") {
                    saveChanges()
                }
                .frame(maxWidth: .infinity)
                .disabled(!hasChanges)
            }
        }
        .navigationTitle(record.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("この避難者を削除")
            }
        }
        .confirmationDialog(
            "「\(record.name)」を削除しますか？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                deleteRecord()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この避難者の記録を削除します。この操作は取り消せません。")
        }
        .alert("保存しました", isPresented: $showSaved) {
            Button("OK") { dismiss() }
        }
    }

    private var hasChanges: Bool {
        injuryStatus != record.injuryStatus || selectedNeeds != Set(record.specialNeeds)
    }

    private func saveChanges() {
        var updated = record
        updated.injuryStatus = injuryStatus
        updated.specialNeeds = Array(selectedNeeds)
        try? db.save(&updated)
        showSaved = true
    }

    private func deleteRecord() {
        try? db.delete(record)
        dismiss()
    }

    private func labelRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年MM月dd日"
        return f.string(from: date)
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: date)
    }
}

// MARK: - 家族グループメンバー表示

struct FamilyMembersSection: View {
    let familyGroupId: String
    let currentId: Int64?
    @EnvironmentObject var db: DatabaseService
    @State private var members: [EvacueeRecord] = []

    var body: some View {
        Group {
            if members.isEmpty {
                Text("メンバー読み込み中...")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(members.filter { $0.id != currentId }) { m in
                    HStack {
                        Text(m.name).font(.subheadline)
                        Spacer()
                        let needs = m.specialNeeds
                        if !needs.isEmpty {
                            HStack(spacing: 2) {
                                ForEach(needs, id: \.self) { Text($0.icon).font(.caption) }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            members = (try? db.fetchFamilyMembers(groupId: familyGroupId)) ?? []
        }
    }
}

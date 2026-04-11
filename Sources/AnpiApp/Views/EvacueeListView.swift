import SwiftUI

struct EvacueeListView: View {
    @EnvironmentObject var db: DatabaseService
    @State private var records: [EvacueeRecord] = []
    @State private var showError = false
    @State private var errorMsg = ""
    @State private var showFilter = false
    @State private var showHelp = false

    // フィルター状態
    @State private var filterFemale = false
    @State private var filterChildren = false
    @State private var filterSpecialNeeds = false
    @State private var filterFamilyGroup = false

    private var filteredRecords: [EvacueeRecord] {
        records.filter { r in
            if filterFemale && r.gender != .female { return false }
            if filterChildren && !(r.ageGroup == .infant || r.ageGroup == .child) { return false }
            if filterSpecialNeeds && r.specialNeeds.isEmpty { return false }
            if filterFamilyGroup && r.familyGroupId == nil { return false }
            return true
        }
    }

    private var isFiltering: Bool {
        filterFemale || filterChildren || filterSpecialNeeds || filterFamilyGroup
    }

    var body: some View {
        Group {
            if records.isEmpty {
                emptyView
            } else {
                VStack(spacing: 0) {
                    // フィルターチップ
                    if isFiltering {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                filterChip("女性", active: filterFemale) { filterFemale.toggle() }
                                filterChip("子供・乳幼児", active: filterChildren) { filterChildren.toggle() }
                                filterChip("配慮事項あり", active: filterSpecialNeeds) { filterSpecialNeeds.toggle() }
                                filterChip("家族グループ", active: filterFamilyGroup) { filterFamilyGroup.toggle() }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        Divider()
                    }

                    List(filteredRecords) { r in
                        NavigationLink(destination: EvacueeDetailView(record: r)) {
                            evacueeRow(r)
                        }
                    }
                    .refreshable { reload() }
                }
            }
        }
        .navigationTitle("避難者一覧（\(filteredRecords.count)/\(records.count)件）")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                Button {
                    showFilter = true
                } label: {
                    Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                NavigationLink("CSV出力") { ExportView() }
            }
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .sheet(isPresented: $showFilter) {
            FilterView(
                filterFemale: $filterFemale,
                filterChildren: $filterChildren,
                filterSpecialNeeds: $filterSpecialNeeds,
                filterFamilyGroup: $filterFamilyGroup
            )
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMsg)
        }
        .onAppear { reload() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var emptyView: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                "登録者なし",
                systemImage: "person.3",
                description: Text("避難者を登録してください")
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "person.3")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("登録者なし")
                    .font(.title3).foregroundStyle(.secondary)
                Text("避難者を登録してください")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func evacueeRow(_ r: EvacueeRecord) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(r.name).font(.headline)
                    // 配慮事項アイコン
                    let needs = r.specialNeeds
                    if !needs.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(needs, id: \.self) { need in
                                Text(need.icon).font(.caption)
                            }
                        }
                    }
                    if r.isEmergencyMode {
                        Text("緊急")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.red.opacity(0.15), in: Capsule())
                            .foregroundStyle(.red)
                    } else {
                        Text("テスト")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.gray.opacity(0.15), in: Capsule())
                            .foregroundStyle(.gray)
                    }
                }
                Text(r.address.isEmpty ? "住所未登録" : r.address)
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("怪我: \(r.injuryStatus)　\(r.gender.label)　\(r.ageGroup.label)")
                    .font(.caption).foregroundStyle(.secondary)
                if let lat = r.latitude, let lon = r.longitude {
                    Text("📍 \(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(r.createdAt, style: .time)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func filterChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(active ? Color.blue : Color.gray.opacity(0.15), in: Capsule())
                .foregroundStyle(active ? .white : .primary)
        }
    }

    // MARK: - Logic

    private func reload() {
        do {
            records = try db.fetchAll()
        } catch {
            errorMsg = error.localizedDescription
            showError = true
        }
    }
}

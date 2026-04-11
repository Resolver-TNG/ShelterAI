import SwiftUI

/// 記録タブのホーム画面（新規登録ボタン + 避難者一覧 + ツールバー）
///
/// 既存の `EvacueeListView` のロジックをインライン化しつつ、
/// 上部に「新規登録」ボタンを追加して `ManualInputView` への導線を一本化する。
struct RegistrationHomeView: View {
    let isEmergencyMode: Bool

    @EnvironmentObject var db: DatabaseService
    @EnvironmentObject var location: LocationService

    @State private var records: [EvacueeRecord] = []
    @State private var showError = false
    @State private var errorMsg = ""
    @State private var showFilter = false
    @State private var showHelp = false
    @State private var showInput = false
    @State private var showDistribution = false
    // CSV出力画面の表示制御（Menu内 NavigationLink は挙動が不安定なため
    // Button + navigationDestination(isPresented:) パターンに置き換え）
    @State private var showExport = false
    // テストデータ全削除確認ダイアログ
    @State private var showDeleteTestDataConfirm = false
    // 検索バー
    @State private var searchText: String = ""

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
            // 検索バー: 名前 or 住所の部分一致（大文字小文字無視）
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !q.isEmpty {
                let nameMatch = r.name.lowercased().contains(q)
                let addressMatch = r.address.lowercased().contains(q)
                if !nameMatch && !addressMatch { return false }
            }
            return true
        }
    }

    private var isFiltering: Bool {
        filterFemale || filterChildren || filterSpecialNeeds || filterFamilyGroup
    }

    var body: some View {
        VStack(spacing: 0) {
            // 上部: モード表示 + 新規登録ボタン
            VStack(spacing: 12) {
                HStack {
                    if isEmergencyMode {
                        Label("緊急事態モード", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).bold()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.red.opacity(0.15), in: Capsule())
                            .foregroundStyle(.red)
                    } else {
                        Label("テストモード", systemImage: "wrench.fill")
                            .font(.caption).bold()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.gray.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("登録: \(records.count)件")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Button {
                    if isEmergencyMode {
                        location.requestPermission()
                        location.start()
                    }
                    showInput = true
                } label: {
                    Label("新規登録", systemImage: "plus.circle.fill")
                        .font(.title3).bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(isEmergencyMode ? .red : .blue)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider()

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
                    .padding(.vertical, 6)
                }
                Divider()
            }

            // 一覧（または空状態）
            // .searchable は List にも 検索ヒット0件表示にも付与するため、コンテナを外側でラップして .searchable は一点だけ付ける
            Group {
                if records.isEmpty {
                    emptyView
                } else if filteredRecords.isEmpty {
                    // 検索ヒット0件のときは ContentUnavailableView を表示
                    if #available(iOS 17.0, *) {
                        ContentUnavailableView.search(text: searchText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack {
                            Spacer()
                            Text("「\(searchText)」に一致する避難者は見つかりません")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding()
                            Spacer()
                        }
                    }
                } else {
                    List(filteredRecords) { r in
                        NavigationLink(destination: EvacueeDetailView(record: r)) {
                            evacueeRow(r)
                        }
                    }
                    .refreshable { reload() }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "名前・住所で検索"
            )
        }
        .navigationTitle("記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ExitToModeSelectionButton()
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showFilter = true
                    } label: {
                        Label(isFiltering ? "フィルター（適用中）" : "フィルター",
                              systemImage: "line.3.horizontal.decrease.circle")
                    }
                    // Menu内の NavigationLink は外側 NavigationStack に解決される
                    // 不安定挙動があるため Button + navigationDestination(isPresented:) に変更
                    Button {
                        showExport = true
                    } label: {
                        Label("CSV出力", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showDistribution = true
                    } label: {
                        Label("配布管理", systemImage: "shippingbox")
                    }
                    Button {
                        showHelp = true
                    } label: {
                        Label("ヘルプ", systemImage: "questionmark.circle")
                    }

                    // テストモード時のみ: サンプルデータ投入 + テストデータ全削除
                    if !isEmergencyMode {
                        Divider()
                        Button {
                            seedSampleData()
                        } label: {
                            Label("サンプルデータを投入", systemImage: "square.and.arrow.down.fill")
                        }
                        Button(role: .destructive) {
                            showDeleteTestDataConfirm = true
                        } label: {
                            Label("テストデータ全削除", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showInput) {
            ManualInputView(isEmergencyMode: isEmergencyMode)
        }
        .navigationDestination(isPresented: $showDistribution) {
            DistributionListView()
        }
        .navigationDestination(isPresented: $showExport) {
            ExportView()
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
        // テストデータ全削除の確認ダイアログ
        .confirmationDialog(
            "テストデータ \(records.count)件を削除しますか？",
            isPresented: $showDeleteTestDataConfirm,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                try? db.deleteTestData()
                reload()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。")
        }
        .onAppear { reload() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var emptyView: some View {
        VStack {
            Spacer()
            if #available(iOS 17.0, *) {
                ContentUnavailableView(
                    "登録者なし",
                    systemImage: "person.3",
                    description: Text("「新規登録」から避難者を追加してください")
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "person.3")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("登録者なし")
                        .font(.title3).foregroundStyle(.secondary)
                    Text("「新規登録」から避難者を追加してください")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func evacueeRow(_ r: EvacueeRecord) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(r.name).font(.headline)
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

    /// テストモード用サンプルデータを一括投入する
    private func seedSampleData() {
        do {
            try SampleDataSeeder.seed(into: db)
            reload()
        } catch {
            errorMsg = "サンプルデータの投入に失敗しました: \(error.localizedDescription)"
            showError = true
        }
    }
}

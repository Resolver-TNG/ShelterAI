import SwiftUI

/// 配布管理トップ画面（配布イベント一覧 + 新規作成）
struct DistributionListView: View {
    @EnvironmentObject var db: DatabaseService
    @State private var distributions: [Distribution] = []
    @State private var showNewSheet = false
    @State private var newItemName = ""
    @State private var errorMsg: String?
    @State private var showError = false

    var body: some View {
        Group {
            if distributions.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView(
                        "配布記録なし",
                        systemImage: "shippingbox",
                        description: Text("右上の＋から配布物資を登録してください")
                    )
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("配布記録なし").font(.title3).foregroundStyle(.secondary)
                        Text("右上の＋から配布物資を登録").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                List {
                    ForEach(distributions) { dist in
                        NavigationLink(destination: DistributionCheckView(distribution: dist)) {
                            distributionRow(dist)
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            try? db.deleteDistribution(distributions[i])
                        }
                        reload()
                    }
                }
            }
        }
        .navigationTitle("配布管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewSheet) {
            newDistributionSheet
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK") {}
        } message: { Text(errorMsg ?? "") }
        .onAppear { reload() }
        .refreshable { reload() }
    }

    // MARK: - Row

    private func distributionRow(_ dist: Distribution) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(dist.itemName).font(.headline)
                Text(dist.createdAt, style: .date)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // 進捗バッジ
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(dist.deliveredCount)/\(dist.totalCount)")
                    .font(.title3).bold()
                    .foregroundStyle(dist.deliveredCount == dist.totalCount ? .green : .orange)
                Text(dist.deliveredCount == dist.totalCount ? "完了" : "配布中")
                    .font(.caption2)
                    .foregroundStyle(dist.deliveredCount == dist.totalCount ? .green : .orange)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - New Distribution Sheet

    private var newDistributionSheet: some View {
        NavigationStack {
            Form {
                Section("配布する物資名") {
                    TextField("例: 非常食、毛布、水（2L）", text: $newItemName)
                        .autocorrectionDisabled()
                }
                Section {
                    Button("配布リストを作成") {
                        createDistribution()
                    }
                    .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("新規配布登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        newItemName = ""
                        showNewSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Logic

    private func createDistribution() {
        do {
            _ = try db.createDistribution(itemName: newItemName.trimmingCharacters(in: .whitespaces))
            newItemName = ""
            showNewSheet = false
            reload()
        } catch {
            errorMsg = error.localizedDescription
            showError = true
        }
    }

    private func reload() {
        distributions = (try? db.fetchAllDistributions()) ?? []
    }
}

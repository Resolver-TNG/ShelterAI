import SwiftUI

/// 配布チェックリスト画面（避難者ごとにチェックボックス）
struct DistributionCheckView: View {
    let distribution: Distribution
    @EnvironmentObject var db: DatabaseService
    @EnvironmentObject var audio: AudioService

    @State private var checkItems: [(item: DistributionCheckItem, evacuee: EvacueeRecord)] = []
    @State private var searchText = ""
    @State private var showError = false
    @State private var errorMsg = ""

    private var filtered: [(item: DistributionCheckItem, evacuee: EvacueeRecord)] {
        if searchText.isEmpty { return checkItems }
        return checkItems.filter {
            $0.evacuee.name.contains(searchText) ||
            $0.evacuee.address.contains(searchText)
        }
    }

    private var deliveredCount: Int { checkItems.filter { $0.item.isDelivered }.count }
    private var totalCount: Int { checkItems.count }
    private var progress: Double { totalCount == 0 ? 0 : Double(deliveredCount) / Double(totalCount) }

    var body: some View {
        VStack(spacing: 0) {
            // 進捗バー
            progressHeader

            // 検索バー
            if !checkItems.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("氏名・住所で検索", text: $searchText)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal).padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
            }

            // チェックリスト
            List(filtered, id: \.item.id) { pair in
                checkRow(pair: pair)
            }
            .listStyle(.plain)
        }
        .navigationTitle(distribution.itemName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("未配布のみ表示") {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK") {}
        } message: { Text(errorMsg) }
        .onAppear { reload() }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("配布済み").font(.caption).foregroundStyle(.secondary)
                    Text("\(deliveredCount)").font(.largeTitle).bold()
                        .foregroundStyle(deliveredCount == totalCount ? .green : .primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("残り").font(.caption).foregroundStyle(.secondary)
                    Text("\(totalCount - deliveredCount)").font(.largeTitle).bold()
                        .foregroundStyle(totalCount - deliveredCount == 0 ? .green : .orange)
                }
            }
            .padding(.horizontal)

            ProgressView(value: progress)
                .tint(deliveredCount == totalCount ? .green : .blue)
                .padding(.horizontal)

            if deliveredCount == totalCount && totalCount > 0 {
                Label("全員への配布完了", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline).bold()
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Check Row

    private func checkRow(pair: (item: DistributionCheckItem, evacuee: EvacueeRecord)) -> some View {
        Button {
            toggle(pair: pair)
        } label: {
            HStack(spacing: 12) {
                // チェックボックス
                Image(systemName: pair.item.isDelivered ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(pair.item.isDelivered ? .green : .secondary)

                // 避難者情報
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.evacuee.name).font(.body)
                        .foregroundStyle(pair.item.isDelivered ? .secondary : .primary)
                        .strikethrough(pair.item.isDelivered)
                    HStack(spacing: 8) {
                        Text(pair.evacuee.injuryStatus).font(.caption)
                            .foregroundStyle(.secondary)
                        if !pair.evacuee.address.isEmpty {
                            Text(pair.evacuee.address).font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // 配布時刻
                if pair.item.isDelivered, let at = pair.item.deliveredAt {
                    Text(at, style: .time)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private func toggle(pair: (item: DistributionCheckItem, evacuee: EvacueeRecord)) {
        do {
            try db.toggleDelivery(item: pair.item)
            // 配布完了時に音声
            if !pair.item.isDelivered {
                audio.announceComplete(name: pair.evacuee.name)
            }
            reload()
        } catch {
            errorMsg = error.localizedDescription
            showError = true
        }
    }

    private func reload() {
        guard let distId = distribution.id else { return }
        // 現在の避難者リストと同期（新規避難者を追加、orphan を削除、totalCountを更新）
        do {
            try db.syncDistributionCheckItems(distributionId: distId)
        } catch {
            errorMsg = error.localizedDescription
            showError = true
            return
        }
        let raw = (try? db.fetchCheckItems(distributionId: distId)) ?? []
        // 未配布を上に、配布済みを下に並べ替え
        checkItems = raw.sorted { a, b in
            if a.0.isDelivered != b.0.isDelivered { return !a.0.isDelivered }
            return a.1.name < b.1.name
        }.map { (item: $0.0, evacuee: $0.1) }
    }
}

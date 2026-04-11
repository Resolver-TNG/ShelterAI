import SwiftUI

/// 状況ダッシュボード
///
/// 登録データから集計した人数・年齢・性別・怪我・配慮事項と、
/// `ShelterAnalytics.estimateSupplies()` による必要物資概算を表示する。
struct SituationView: View {
    @EnvironmentObject var db: DatabaseService

    @State private var stats: ShelterStats = .empty
    @State private var supplyDays: Double = 3
    @State private var showError = false
    @State private var errorMsg = ""

    private var supplies: SupplyEstimate {
        ShelterAnalytics.estimateSupplies(from: stats, days: Int(supplyDays))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if stats.totalCount == 0 {
                    emptyCard
                } else {
                    summaryCard
                    injuryCard
                    specialNeedsCard
                    genderCard
                    suppliesCard
                }
            }
            .padding()
        }
        .navigationTitle("状況")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ExitToModeSelectionButton()
            }
        }
        .refreshable { reload() }
        .onAppear { reload() }
        .alert("エラー", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMsg)
        }
    }

    // MARK: - Cards

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("登録なし")
                .font(.title3).foregroundStyle(.secondary)
            Text("避難者を登録すると集計が表示されます")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var summaryCard: some View {
        sectionCard(title: "人数サマリー", icon: "person.3.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(stats.totalCount)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("名")
                        .font(.title3).foregroundStyle(.secondary)
                    Spacer()
                }

                Divider()

                let order: [AgeGroup] = [.infant, .child, .adult, .elderly]
                ForEach(order, id: \.self) { g in
                    let n = stats.ageGroups[g] ?? 0
                    if n > 0 || stats.totalCount > 0 {
                        statRow(label: g.label, count: n, total: stats.totalCount)
                    }
                }
            }
        }
    }

    private var injuryCard: some View {
        sectionCard(title: "怪我状況", icon: "cross.case.fill") {
            VStack(alignment: .leading, spacing: 8) {
                let order = ["なし", "軽傷", "中程度", "重傷", "不明"]
                ForEach(order, id: \.self) { key in
                    let n = stats.injuries[key] ?? 0
                    if n > 0 {
                        statRow(label: key, count: n, total: stats.totalCount)
                    }
                }
                if (order.compactMap { stats.injuries[$0] ?? 0 }.reduce(0, +)) == 0 {
                    Text("登録データなし").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var specialNeedsCard: some View {
        sectionCard(title: "配慮事項", icon: "heart.text.square.fill") {
            VStack(alignment: .leading, spacing: 8) {
                let order: [SpecialNeed] = [.infantCare, .sanitary, .wheelchair, .other]
                let active = order.filter { (stats.specialNeeds[$0] ?? 0) > 0 }
                if active.isEmpty {
                    Text("配慮事項の登録なし").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(active, id: \.self) { n in
                        let count = stats.specialNeeds[n] ?? 0
                        HStack {
                            Text(n.label).font(.subheadline)
                            Spacer()
                            Text("\(count)名").font(.subheadline).bold()
                        }
                    }
                }

                if stats.foreignResidents > 0 {
                    Divider()
                    HStack {
                        Text("🌏 外国人避難者（在留カード）").font(.subheadline)
                        Spacer()
                        Text("\(stats.foreignResidents)名").font(.subheadline).bold()
                    }
                }
            }
        }
    }

    private var genderCard: some View {
        sectionCard(title: "性別分布", icon: "person.2.fill") {
            VStack(alignment: .leading, spacing: 8) {
                let order: [Gender] = [.female, .male, .other, .unspecified]
                ForEach(order, id: \.self) { g in
                    let n = stats.genders[g] ?? 0
                    if n > 0 {
                        statRow(label: g.label, count: n, total: stats.totalCount)
                    }
                }
            }
        }
    }

    private var suppliesCard: some View {
        sectionCard(title: "📦 必要物資概算", icon: "shippingbox.fill") {
            VStack(alignment: .leading, spacing: 12) {
                // 日数スライダー
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("対象日数")
                            .font(.subheadline).bold()
                        Spacer()
                        Text("\(Int(supplyDays))日分")
                            .font(.subheadline).foregroundStyle(.blue)
                    }
                    Slider(value: $supplyDays, in: 1...7, step: 1)
                }

                Divider()

                supplyRow(icon: "💧", label: "飲料水",
                          value: "\(Int(supplies.water)) L",
                          note: "3L/人/日")
                supplyRow(icon: "🍙", label: "食料",
                          value: "\(supplies.meals) 食",
                          note: "3食/人/日")
                supplyRow(icon: "🛏️", label: "毛布",
                          value: "\(supplies.blankets) 枚",
                          note: "1枚/人")
                if supplies.diapers > 0 {
                    supplyRow(icon: "👶", label: "おむつ",
                              value: "\(supplies.diapers) 枚",
                              note: "乳幼児×5枚/日")
                }
                if supplies.formula > 0 {
                    supplyRow(icon: "🍼", label: "粉ミルク",
                              value: "\(supplies.formula) 缶",
                              note: "乳幼児×1缶/日")
                }
                if supplies.sanitaryPads > 0 {
                    supplyRow(icon: "🩸", label: "生理用品",
                              value: "\(supplies.sanitaryPads) パック",
                              note: "希望者×1/日")
                }
                if supplies.medicalKits > 0 {
                    supplyRow(icon: "💊", label: "医薬品セット",
                              value: "\(supplies.medicalKits) 人分",
                              note: "怪我ありの方")
                }

                Text("内閣府指針準拠の概算値です。実態に応じて調整してください。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Reusable Components

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func statRow(label: String, count: Int, total: Int) -> some View {
        let ratio = total > 0 ? Double(count) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text("\(count)名").font(.subheadline).bold()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 6)
        }
    }

    private func supplyRow(icon: String, label: String, value: String, note: String) -> some View {
        HStack(alignment: .center) {
            Text(icon).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline).bold()
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).font(.subheadline).bold().foregroundStyle(.blue)
        }
    }

    // MARK: - Logic

    private func reload() {
        do {
            stats = try db.fetchStats()
        } catch {
            errorMsg = error.localizedDescription
            showError = true
        }
    }
}

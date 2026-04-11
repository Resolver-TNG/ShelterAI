import SwiftUI

struct FilterView: View {
    @Binding var filterFemale: Bool
    @Binding var filterChildren: Bool
    @Binding var filterSpecialNeeds: Bool
    @Binding var filterFamilyGroup: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("要配慮者") {
                    Toggle(isOn: $filterFemale) {
                        Label("女性のみ", systemImage: "person.fill")
                    }
                    Toggle(isOn: $filterChildren) {
                        Label("子供・乳幼児のみ", systemImage: "figure.child")
                    }
                    Toggle(isOn: $filterSpecialNeeds) {
                        Label("配慮事項あり", systemImage: "heart.fill")
                    }
                }
                Section("グループ") {
                    Toggle(isOn: $filterFamilyGroup) {
                        Label("家族グループ登録済み", systemImage: "person.2.fill")
                    }
                }
                Section {
                    Button("フィルターをリセット") {
                        filterFemale = false
                        filterChildren = false
                        filterSpecialNeeds = false
                        filterFamilyGroup = false
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}

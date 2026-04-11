import SwiftUI

struct ExportView: View {
    @EnvironmentObject var db: DatabaseService
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var errorMsg: String?

    var body: some View {
        VStack(spacing: 24) {
            Button("CSVファイルを作成") {
                do {
                    let records = try db.fetchAll()
                    shareURL = try CSVExportService.export(records)
                    showShare = true
                } catch { errorMsg = error.localizedDescription }
            }
            .buttonStyle(.borderedProminent)

            if let errorMsg { Text(errorMsg).foregroundStyle(.red) }
        }
        .navigationTitle("CSV出力")
        .sheet(isPresented: $showShare) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
    }
}

// UIKit share sheet wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

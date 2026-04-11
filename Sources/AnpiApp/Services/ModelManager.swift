import Foundation

@MainActor
final class ModelManager: ObservableObject {
    @Published var downloadProgress: Double = 0.0
    @Published var modelStatus: ModelStatus = .notDownloaded

    enum ModelStatus {
        case notDownloaded
        case downloading(progress: Double)
        case ready
        case error(String)
    }

    static let shared = ModelManager()

    /// Bundle内モデルのディレクトリURL
    var bundleModelURL: URL? {
        let path = Bundle.main.bundlePath + "/Models/gemma-4-E2B-coreml"
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: path) ? url : nil
    }

    /// Documents/gemma4 のURL（DL方式用）
    var documentsModelURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gemma4")
    }

    /// モデルが利用可能なディレクトリを返す（Bundle優先）
    var modelDirectoryURL: URL? {
        if let bundleURL = bundleModelURL { return bundleURL }
        let docsPath = documentsModelURL.path
        if FileManager.default.fileExists(atPath: docsPath) { return documentsModelURL }
        return nil
    }

    init() {
        if checkModelExists() {
            modelStatus = .ready
        }
    }

    /// モデルが利用可能か確認（Bundle内蔵 or Documents）
    func checkModelExists() -> Bool {
        // Bundle内蔵チェック（model_config.json の存在で判定）
        if let bundleURL = bundleModelURL {
            let configPath = bundleURL.appendingPathComponent("model_config.json").path
            if FileManager.default.fileExists(atPath: configPath) {
                return true
            }
        }
        // Documents チェック
        let docsConfig = documentsModelURL.appendingPathComponent("model_config.json").path
        return FileManager.default.fileExists(atPath: docsConfig)
    }

    /// モデルダウンロード（将来実装: HuggingFaceからDL）
    /// 現在はBundle内蔵があれば即.readyに遷移
    func downloadModels() async throws {
        if checkModelExists() {
            modelStatus = .ready
            return
        }

        modelStatus = .downloading(progress: 0.0)
        downloadProgress = 0.0

        // TODO: HuggingFaceからの実DL実装
        // 現状はBundle内蔵前提のためエラー
        modelStatus = .error("モデルがBundle内に見つかりません。開発者にお問い合わせください。")
    }

    /// ローカルファイルからモデルをインポート（開発用）
    func importModelFromDirectory(_ sourceURL: URL) throws {
        let fm = FileManager.default
        let dest = documentsModelURL
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: sourceURL, to: dest)
        modelStatus = .ready
    }
}

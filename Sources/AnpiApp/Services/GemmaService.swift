import Foundation
import UIKit
import CoreMLLLM

// MARK: - CardPrompts

enum CardPrompts {
    /// Gemma 4 E2B (2B effective params) 向けの最適化プロンプト。
    ///
    /// 設計方針:
    /// - 短く明確に。Eパラメータモデルはコンテキストが短い方が安定する
    /// - JSONスキーマを例示形式で固定（few-shot不要のフォーマット拘束）
    /// - confidence はモデル自身に算出させず、コード側でフィールド埋まり率から計算
    /// - card_type の選択肢は1行に圧縮し、全体トークン数を削減
    /// - 「読み取れないフィールドは空文字」と明示し、ハルシネーションを抑制
    static let cardExtraction: String = """
    画像は日本の身分証明書です。次のJSONで抽出してください。
    {"card_type":"","name":"","address":"","date_of_birth":""}
    card_typeは: マイナンバーカード, 運転免許証, パスポート, 在留カード, 健康保険証, その他 のいずれか。
    date_of_birthはYYYY年MM月DD日形式。読み取れない項目は空文字。JSONのみ出力。
    """
}

// MARK: - GemmaService

@MainActor
final class GemmaService: ObservableObject {

    // MARK: - Published State

    @Published var isModelLoaded: Bool = false
    @Published var isLoading: Bool = false
    @Published var progressStep: String = ""
    @Published var progressPercent: Int = 0

    // MARK: - Private

    private var llm: CoreMLLLM?

    // 採用ポリシーの閾値
    private let highConfidenceThreshold: Float = 0.8   // これ以上 → Gemma を即採用
    private let lowConfidenceThreshold: Float = 0.5    // これ未満 → Vision OCR を即採用

    // MARK: - Model Loading

    /// CoreMLモデルをロード
    /// - Bundle 内蔵 → Documents/gemma4 の順に解決
    func loadModel() async throws {
        isLoading = true
        defer { isLoading = false }

        let modelURL = try resolveModelDirectoryURL()
        // 必須ファイル（hf_model/tokenizer.json）の事前チェック
        try validateModelDirectory(modelURL)

        print("[GemmaService] Loading CoreMLLLM from: \(modelURL.path)")
        llm = try await CoreMLLLM.load(from: modelURL)
        isModelLoaded = true
    }

    /// モデルディレクトリを解決する。
    ///
    /// 探索順:
    /// 1. `Bundle.main.bundlePath/Models/gemma-4-E2B-coreml`（postBuildScript 配置先）
    /// 2. `Bundle.main.resourceURL/Models/gemma-4-E2B-coreml`（リソースバンドル経由）
    /// 3. `Documents/gemma4`（手動配置/ダウンロードのフォールバック）
    ///
    /// 全て失敗した場合は、探索したパス一覧を含むエラーを投げる。
    private func resolveModelDirectoryURL() throws -> URL {
        var attempted: [String] = []

        // 1. bundlePath 直下
        let bundlePathURL = URL(fileURLWithPath: Bundle.main.bundlePath)
            .appendingPathComponent("Models")
            .appendingPathComponent("gemma-4-E2B-coreml")
        attempted.append(bundlePathURL.path)
        if FileManager.default.fileExists(atPath: bundlePathURL.path) {
            return bundlePathURL
        }

        // 2. resourceURL 経由
        if let resourceURL = Bundle.main.resourceURL {
            let resourceModelURL = resourceURL
                .appendingPathComponent("Models")
                .appendingPathComponent("gemma-4-E2B-coreml")
            attempted.append(resourceModelURL.path)
            if FileManager.default.fileExists(atPath: resourceModelURL.path) {
                return resourceModelURL
            }
        }

        // 3. Documents/gemma4 フォールバック
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gemma4")
        attempted.append(docsURL.path)
        if FileManager.default.fileExists(atPath: docsURL.path) {
            return docsURL
        }

        let message = "Gemma 4 model directory not found. Searched paths:\n" +
            attempted.enumerated().map { "  [\($0.offset + 1)] \($0.element)" }.joined(separator: "\n")
        print("[GemmaService] \(message)")
        throw NSError(
            domain: "GemmaService",
            code: -10,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    /// モデルディレクトリ内に CoreML-LLM が要求する必須ファイルが揃っているか検証。
    /// 不足している場合は具体的にどのファイルが見つからなかったかを示すエラーを投げる。
    private func validateModelDirectory(_ modelURL: URL) throws {
        let fm = FileManager.default

        // CoreML-LLM の CoreMLLLM.load は `<directory>/hf_model/` から tokenizer を読み込む。
        // swift-transformers の AutoTokenizer.from(modelFolder:) は tokenizer.json を必須とし、
        // tokenizer_config.json / chat_template.* は optional 扱い。
        let hfDir = modelURL.appendingPathComponent("hf_model")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: hfDir.path, isDirectory: &isDir), isDir.boolValue else {
            let msg = "hf_model directory missing at: \(hfDir.path)"
            print("[GemmaService] \(msg)")
            throw NSError(
                domain: "GemmaService",
                code: -11,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }

        let tokenizerJSON = hfDir.appendingPathComponent("tokenizer.json")
        guard fm.fileExists(atPath: tokenizerJSON.path) else {
            let msg = "tokenizer.json missing at: \(tokenizerJSON.path)"
            print("[GemmaService] \(msg)")
            throw NSError(
                domain: "GemmaService",
                code: -12,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }

        // 任意ファイルは欠けていてもログのみ
        let tokenizerConfig = hfDir.appendingPathComponent("tokenizer_config.json")
        if !fm.fileExists(atPath: tokenizerConfig.path) {
            print("[GemmaService] note: tokenizer_config.json not found (optional). Path: \(tokenizerConfig.path)")
        }
    }

    // MARK: - Card Analysis (Public)

    /// カード画像を解析して CardAnalysisResult を返す。
    ///
    /// ハイブリッド推論:
    /// - 前処理 → Gemma 4 と Vision OCR を並列実行
    /// - Gemma confidence > 0.8 → Gemma 採用
    /// - Gemma confidence < 0.5 / 失敗 → Vision OCR 採用
    /// - 中間域 → フィールドごとに長い方を採用してマージ
    /// プログレスコールバックの型
    typealias ProgressCallback = (_ step: String, _ percent: Int) -> Void

    func analyzeCard(image: UIImage, onProgress: ProgressCallback? = nil) async throws -> CardAnalysisResult {
        isLoading = true
        defer { isLoading = false }

        // 0. 初期化（描画機会を確保）
        await updateProgress(percent: 5, step: "解析を開始しています...", onProgress: onProgress, key: "start")

        // 1. 前処理（タイムアウト付き、失敗時は元画像を使用）
        await updateProgress(percent: 15, step: "画像を前処理中...", onProgress: onProgress, key: "preprocess")
        let preprocessed: UIImage = await withTimeout(seconds: 3) {
            await CardPreprocessor.process(image)
        } ?? image

        // 2. Vision OCR を実行（メイン、確実に動く方）
        await updateProgress(percent: 35, step: "Vision OCRで読み取り中...", onProgress: onProgress, key: "ocr")
        let ocr: CardAnalysisResult
        do {
            ocr = try await runVisionOCR(image: preprocessed)
        } catch {
            // OCRも失敗 → 空の結果を返す（手動入力に誘導）
            ocr = CardAnalysisResult(
                cardType: .other,
                name: "",
                address: "",
                dateOfBirth: "",
                confidence: 0.0,
                rawResponse: "(OCR failed: \(error.localizedDescription))"
            )
        }

        // 3. Gemma推論を試行（モデルがある場合のみ）
        await updateProgress(percent: 60, step: "Gemma 4 AIが推論中...", onProgress: onProgress, key: "gemma")
        let gemma = await runGemma(image: preprocessed)

        await updateProgress(percent: 85, step: "結果を整理中...", onProgress: onProgress, key: "postprocess")

        // 4. 採用ポリシー
        let finalResult: CardAnalysisResult
        if let gemma = gemma {
            if gemma.confidence >= highConfidenceThreshold {
                finalResult = postProcess(gemma)
            } else if gemma.confidence < lowConfidenceThreshold {
                finalResult = postProcess(ocr)
            } else {
                // 中間: フィールドごとに長い方を採用してマージ
                finalResult = postProcess(merge(gemma: gemma, ocr: ocr))
            }
        } else {
            // Gemma が無い/失敗 → OCR
            finalResult = postProcess(ocr)
        }

        await updateProgress(percent: 100, step: "完了", onProgress: onProgress, key: "done")
        return finalResult
    }

    /// プログレス更新 + Viewが再描画される機会を作る
    /// `Task.yield()` だけだとMainActor上の連続更新が中間値を飛ばすため、
    /// 短いsleepでrunloopにrender機会を渡す
    private func updateProgress(
        percent: Int,
        step: String,
        onProgress: ProgressCallback?,
        key: String
    ) async {
        progressPercent = percent
        progressStep = step
        onProgress?(key, percent)
        // SwiftUIのrender機会を確保（ステップごとの%表示が確実に出る）
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
    }

    /// タイムアウト付き非同期実行
    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    // MARK: - Gemma Inference

    /// Gemma 4 で推論し、CardAnalysisResult? を返す。失敗時は nil。
    private func runGemma(image: UIImage) async -> CardAnalysisResult? {
        guard let llm = llm, let cgImage = image.cgImage else {
            return nil
        }

        let fullResponse: String
        do {
            // CoreMLLLM.generate(_:image:audio:maxTokens:) は完成文字列を返す。
            // ストリーミングが必要な場面では llm.stream(...) を利用する。
            fullResponse = try await llm.generate(
                [CoreMLLLM.Message(role: .user, content: CardPrompts.cardExtraction)],
                image: cgImage,
                maxTokens: 256
            )
        } catch {
            return nil
        }

        return parseCardJSON(fullResponse)
    }

    // MARK: - Vision OCR Fallback

    /// Vision OCR を実行し、CardAnalysisResult に変換
    private func runVisionOCR(image: UIImage) async throws -> CardAnalysisResult {
        let info = try await CardOCRService.recognize(image: image)
        let allText = [info.name, info.address, info.dateOfBirth].joined(separator: " ")
        return CardAnalysisResult(
            cardType: detectCardType(from: allText),
            name: info.name,
            address: info.address,
            dateOfBirth: info.dateOfBirth,
            confidence: 0.70,  // OCR は固定の中信頼度
            rawResponse: "(Vision OCR) \(allText)"
        )
    }

    // MARK: - Merge Strategy

    /// Gemma と OCR の結果をフィールドごとに突き合わせ、長い方（情報量が多い方）を採用
    private func merge(gemma: CardAnalysisResult, ocr: CardAnalysisResult) -> CardAnalysisResult {
        func pickLonger(_ a: String, _ b: String) -> String {
            let aTrim = a.trimmingCharacters(in: .whitespacesAndNewlines)
            let bTrim = b.trimmingCharacters(in: .whitespacesAndNewlines)
            if aTrim.isEmpty { return bTrim }
            if bTrim.isEmpty { return aTrim }
            return aTrim.count >= bTrim.count ? aTrim : bTrim
        }

        // CardType: Gemma が「その他」なら OCR の推定を採用
        let cardType: CardType
        if gemma.cardType == .other && ocr.cardType != .other {
            cardType = ocr.cardType
        } else {
            cardType = gemma.cardType
        }

        return CardAnalysisResult(
            cardType: cardType,
            name: pickLonger(gemma.name, ocr.name),
            address: pickLonger(gemma.address, ocr.address),
            dateOfBirth: pickLonger(gemma.dateOfBirth, ocr.dateOfBirth),
            // 中間域なのでマージ後もやや低めに保つ
            confidence: max(gemma.confidence, ocr.confidence) * 0.95,
            rawResponse: "(Hybrid merged)\nGemma: \(gemma.rawResponse)\nOCR: \(ocr.rawResponse)"
        )
    }

    // MARK: - Post Processing

    /// 後処理: 住所正規化、和暦→西暦変換
    private func postProcess(_ result: CardAnalysisResult) -> CardAnalysisResult {
        var r = result
        r.address = AddressNormalizer.normalize(r.address)
        r.dateOfBirth = convertWarekiToSeireki(r.dateOfBirth)
        return r
    }

    // MARK: - JSON Parsing (Robust)

    /// Gemma の応答から JSON を抽出 → 修復 → パース
    private func parseCardJSON(_ response: String) -> CardAnalysisResult? {
        guard let raw = extractJSONString(from: response) else { return nil }
        let repaired = repairJSON(raw)

        guard let data = repaired.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let cardTypeStr = (json["card_type"] as? String) ?? "その他"
        let cardType = CardType(rawValue: cardTypeStr) ?? .other

        let name = (json["name"] as? String) ?? ""
        let address = (json["address"] as? String) ?? ""
        let dateOfBirth = (json["date_of_birth"] as? String) ?? ""

        // confidence はモデル自身が出すと不正確なので、フィールド埋まり率から算出する。
        // name / address / date_of_birth の3フィールドのうち、空でないものの割合 × 0.9。
        // 0.9 を上限とするのは、Gemma単体推論でも完璧ではない可能性を残すため。
        let fields = [name, address, dateOfBirth]
        let filledCount = fields.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let confidence = Float(filledCount) / Float(fields.count) * 0.9

        return CardAnalysisResult(
            cardType: cardType,
            name: name,
            address: address,
            dateOfBirth: dateOfBirth,
            confidence: confidence,
            rawResponse: response
        )
    }

    /// 応答テキストから JSON 部分を抽出
    /// 1. ```json ... ``` ブロック → 中身を取得
    /// 2. プレーンな { ... }（最初の `{` から最後の `}` まで貪欲に）
    private func extractJSONString(from response: String) -> String? {
        // ```json ... ```
        if let mdRange = response.range(of: "```(?:json)?\\s*([\\s\\S]*?)```", options: .regularExpression) {
            let block = String(response[mdRange])
            if let inner = block.range(of: "\\{[\\s\\S]*\\}", options: .regularExpression) {
                return String(block[inner])
            }
        }
        // プレーン { ... } (最後の } まで)
        if let firstBrace = response.firstIndex(of: "{"),
           let lastBrace = response.lastIndex(of: "}"),
           firstBrace < lastBrace {
            return String(response[firstBrace...lastBrace])
        }
        return nil
    }

    /// 不完全 JSON の修復:
    /// - 末尾カンマ削除
    /// - 中括弧の閉じ忘れを補完
    /// - シングルクオートをダブルクオートに変換
    private func repairJSON(_ raw: String) -> String {
        var s = raw

        // シングルクオート → ダブルクオート（ただし内部のダブルクオートは触らない）
        if !s.contains("\"") && s.contains("'") {
            s = s.replacingOccurrences(of: "'", with: "\"")
        }

        // 末尾カンマ ", }" や ", ]" を除去
        s = s.replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)
        s = s.replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)

        // 中括弧の数合わせ
        let openCount = s.filter { $0 == "{" }.count
        let closeCount = s.filter { $0 == "}" }.count
        if openCount > closeCount {
            s += String(repeating: "}", count: openCount - closeCount)
        }

        return s
    }

    // MARK: - 和暦 → 西暦 変換

    /// "昭和65年1月1日" のような和暦表記を "1990年01月01日" に変換
    /// 既に西暦表記なら正規化のみ（区切り文字統一）
    private func convertWarekiToSeireki(_ date: String) -> String {
        let trimmed = date.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }

        // 既に西暦
        let seirekiPattern = #"^((?:19|20)\d{2})[年./\-](\d{1,2})[月./\-](\d{1,2})日?$"#
        if let match = trimmed.range(of: seirekiPattern, options: .regularExpression) {
            return formatSeireki(String(trimmed[match]))
        }

        // 和暦
        let warekiPattern = #"(明治|大正|昭和|平成|令和)(\d{1,2})年(\d{1,2})月(\d{1,2})日"#
        guard let regex = try? NSRegularExpression(pattern: warekiPattern),
              let match = regex.firstMatch(
                  in: trimmed,
                  range: NSRange(trimmed.startIndex..., in: trimmed)
              ),
              match.numberOfRanges == 5 else {
            return trimmed
        }

        func substring(_ idx: Int) -> String {
            guard let r = Range(match.range(at: idx), in: trimmed) else { return "" }
            return String(trimmed[r])
        }

        let era = substring(1)
        guard let eraYear = Int(substring(2)),
              let month = Int(substring(3)),
              let day = Int(substring(4)) else {
            return trimmed
        }

        let baseYear: Int
        switch era {
        case "明治": baseYear = 1867   // 明治1年 = 1868
        case "大正": baseYear = 1911   // 大正1年 = 1912
        case "昭和": baseYear = 1925   // 昭和1年 = 1926
        case "平成": baseYear = 1988   // 平成1年 = 1989
        case "令和": baseYear = 2018   // 令和1年 = 2019
        default:    return trimmed
        }
        let year = baseYear + eraYear

        return String(format: "%04d年%02d月%02d日", year, month, day)
    }

    /// 西暦表記の区切りを "YYYY年MM月DD日" に統一
    private func formatSeireki(_ s: String) -> String {
        let pattern = #"((?:19|20)\d{2})[年./\-](\d{1,2})[月./\-](\d{1,2})日?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              match.numberOfRanges == 4 else {
            return s
        }
        func sub(_ i: Int) -> String {
            guard let r = Range(match.range(at: i), in: s) else { return "" }
            return String(s[r])
        }
        guard let year = Int(sub(1)),
              let month = Int(sub(2)),
              let day = Int(sub(3)) else { return s }
        return String(format: "%04d年%02d月%02d日", year, month, day)
    }

    // MARK: - Card Type Detection (OCR Fallback)

    private func detectCardType(from text: String) -> CardType {
        if text.contains("マイナンバー") || text.contains("個人番号") { return .mynumber }
        if text.contains("免許証") || text.contains("運転免許") { return .driverLicense }
        if text.contains("PASSPORT") || text.contains("パスポート") || text.contains("旅券") { return .passport }
        if text.contains("在留") { return .residenceCard }
        if text.contains("保険証") || text.contains("健康保険") { return .healthInsurance }
        return .other
    }

    // MARK: - Chat (AI Assistant)

    /// 避難所AIアシスタント用プロンプトビルダー
    ///
    /// Gemma 4 E2B (2B effective params) 向け最適化:
    /// - system role は無視されがちなので **user message に全部埋め込む**
    /// - 冒頭でロール（災害対策AI）を強く宣言
    /// - データを明示的に区切り線で囲み、「このデータだけ」と繰り返す
    /// - 末尾「回答:」トークンで前置きなしの即答へ誘導
    /// - 「終わったら止まる」を明示し生成オーバーランを防ぐ
    /// - 絶対ルールでデータ外推測を禁止し、ハルシネーションを抑制
    /// - context制約に配慮しトークン効率を最適化（短く・密に）
    static func buildPrompt(context: String, question: String) -> String {
        """
        あなたは避難所災害対策AI。避難所運営者の質問に答える。

        ===避難所の登録データ===
        \(context)
        ===データここまで===

        【ルール】
        - 人数・名前・物資などの具体的データは上の登録データを参照して正確に答える。
        - 避難所運営の一般的な知識（衛生管理、炊き出し、心のケア、設備の作り方など）は、登録データになくても答えてよい。
        - 回答は箇条書き、簡潔に。終わったら止まる。
        - 前置き不要。即答する。

        質問: \(question)
        回答:
        """
    }

    /// 会話用生成メソッド（ストリーミング対応）
    ///
    /// E2B向け: system roleを使わず、全てをuser messageに埋め込む。
    /// 小型モデルはsystem roleの遵守力が低いため、single-turn user promptが最も安定。
    ///
    /// maxTokens=384: E2Bは長文で品質が下がるため短く制限。
    func chat(
        contextText: String,
        userMessage: String,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard let llm = llm else {
            throw NSError(
                domain: "GemmaService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AIモデルがロードされていません。「AIモデルを読み込む」を押してください。"]
            )
        }

        // E2B最適化: system roleを使わず、user messageに全て埋め込む
        let fullPrompt = Self.buildPrompt(context: contextText, question: userMessage)

        let messages: [CoreMLLLM.Message] = [
            CoreMLLLM.Message(role: .user, content: fullPrompt),
        ]

        var fullText = ""
        let stream = try await llm.stream(messages, maxTokens: 384)
        for await token in stream {
            fullText += token
            onToken(token)
        }
        return fullText
    }
}

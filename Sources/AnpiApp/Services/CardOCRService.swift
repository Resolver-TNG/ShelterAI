import Vision
import UIKit

/// Vision OCRでカード画像から基本情報を抽出するサービス
struct CardOCRService {

    struct CardInfo {
        var name: String = ""
        var address: String = ""
        var dateOfBirth: String = ""  // "YYYY年MM月DD日" 形式
    }

    /// UIImageからOCRを実行してCardInfoを返す
    static func recognize(image: UIImage) async throws -> CardInfo {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: CardInfo())
                    return
                }

                let lines = observations.compactMap { obs in
                    obs.topCandidates(1).first?.string
                }

                let info = parse(lines: lines)
                continuation.resume(returning: info)
            }

            // 日本語＋英語テキスト認識
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - パース処理

    /// OCRで認識したテキスト行から氏名・住所・生年月日を抽出
    ///
    /// 対応カード:
    /// - マイナンバーカード / 運転免許証（日本語ラベル: 氏名・住所・生年月日）
    /// - 在留カード（英語ラベル併記: Name / Address / Date of birth）
    /// - パスポート（MRZパターン `P<JPN...` から判定、生年月日はMRZ第2行から抽出）
    static func parse(lines: [String]) -> CardInfo {
        var info = CardInfo()

        // パスポートMRZ判定 → 専用パーサで先に処理
        if let mrzInfo = parsePassportMRZ(lines: lines) {
            info = mrzInfo
            // MRZで埋まらなかったフィールドは通常パースで補完
        }

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 氏名ラベル（日本語/英語）
            if info.name.isEmpty,
               trimmed.contains("氏名") || trimmed.contains("ふりがな") ||
               containsLabel(trimmed, label: "Name") {
                if let name = extractAfterLabel(line: trimmed, labels: ["氏名", "Name"]), !name.isEmpty {
                    info.name = name
                } else if i + 1 < lines.count {
                    let nextLine = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if !looksLikeLabel(nextLine), nextLine.count > 1 {
                        info.name = nextLine
                    }
                }
            }

            // 住所（日本語/英語）
            if info.address.isEmpty,
               trimmed.contains("住所") || trimmed.contains("居住地") ||
               containsLabel(trimmed, label: "Address") {
                if let addr = extractAfterLabel(line: trimmed, labels: ["住所", "居住地", "Address"]), !addr.isEmpty {
                    info.address = addr
                } else if i + 1 < lines.count {
                    var addr = ""
                    for j in (i + 1)..<min(i + 4, lines.count) {
                        let nextLine = lines[j].trimmingCharacters(in: .whitespaces)
                        if looksLikeLabel(nextLine) { break }
                        addr += nextLine
                    }
                    if !addr.isEmpty { info.address = addr }
                }
            }

            // 生年月日（日本語/英語）
            if info.dateOfBirth.isEmpty,
               trimmed.contains("生年月日") || containsLabel(trimmed, label: "Date of birth") {
                if let dob = extractDate(from: trimmed) {
                    info.dateOfBirth = dob
                } else if i + 1 < lines.count {
                    if let dob = extractDate(from: lines[i + 1]) {
                        info.dateOfBirth = dob
                    }
                }
            }

            // 直接日付パターンを検出（"昭和/平成/令和XX年XX月XX日" or 西暦）
            if info.dateOfBirth.isEmpty, let dob = extractDate(from: trimmed) {
                info.dateOfBirth = dob
            }
        }

        // 名前ヒューリスティクス: ラベル検出に失敗した場合、人名らしい行を推定
        if info.name.isEmpty {
            info.name = guessNameLine(lines: lines)
        }

        return info
    }

    // MARK: - パスポートMRZパーサ

    /// パスポートのMRZ（Machine Readable Zone）を解析
    /// MRZは2行構成で、`P<JPN...` のような国コードプレフィックスで始まる
    /// - 第1行: P<JPN<SURNAME<<GIVEN<NAMES<<<...
    /// - 第2行: PASSPORTNO<JPN<YYMMDD<...（位置14-19が生年月日 YYMMDD）
    static func parsePassportMRZ(lines: [String]) -> CardInfo? {
        // P<JPN または P<で始まる行を探す（OCRノイズに耐えるため緩めに）
        var mrzLine1: String?
        var mrzLine2: String?

        for (i, line) in lines.enumerated() {
            let upper = line.replacingOccurrences(of: " ", with: "").uppercased()
            if mrzLine1 == nil, upper.hasPrefix("P<") {
                mrzLine1 = upper
                if i + 1 < lines.count {
                    mrzLine2 = lines[i + 1].replacingOccurrences(of: " ", with: "").uppercased()
                }
                break
            }
        }

        guard let line1 = mrzLine1 else { return nil }

        var info = CardInfo()

        // 第1行から氏名抽出: P<XXX<SURNAME<<GIVEN<NAMES<<<
        // フォーマット: P<{国コード3}<{姓}<<{名}<...
        if let nameStart = line1.range(of: "<", options: .backwards, range: line1.startIndex..<line1.index(line1.startIndex, offsetBy: min(6, line1.count))) {
            let _ = nameStart  // 位置取得のみ
        }
        // 簡易: P< のあとの最初の `<<` までが姓、その後の `<<<` までが名
        let afterPrefix = String(line1.dropFirst(2)) // "JPN<SURNAME<<GIVEN..."
        let afterCountry = afterPrefix.dropFirst(min(4, afterPrefix.count)) // 国コード3+`<` をスキップ
        let nameField = String(afterCountry)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<"))
        let nameParts = nameField.components(separatedBy: "<<")
        if nameParts.count >= 2 {
            let surname = nameParts[0].replacingOccurrences(of: "<", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let given = nameParts[1].replacingOccurrences(of: "<", with: " ")
                .trimmingCharacters(in: .whitespaces)
            if !surname.isEmpty && !given.isEmpty {
                info.name = "\(surname) \(given)"
            }
        }

        // 第2行から生年月日抽出（位置14-19の YYMMDD）
        if let line2 = mrzLine2, line2.count >= 20 {
            let dobRange = line2.index(line2.startIndex, offsetBy: 13)..<line2.index(line2.startIndex, offsetBy: 19)
            let yymmdd = String(line2[dobRange])
            if yymmdd.allSatisfy({ $0.isNumber }) {
                let yy = Int(yymmdd.prefix(2)) ?? 0
                let mm = Int(yymmdd.dropFirst(2).prefix(2)) ?? 0
                let dd = Int(yymmdd.dropFirst(4).prefix(2)) ?? 0
                // 2桁年: 30以下→2000年代、それ以上→1900年代と推定
                let yyyy = yy <= 30 ? 2000 + yy : 1900 + yy
                if mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31 {
                    info.dateOfBirth = String(format: "%04d年%02d月%02d日", yyyy, mm, dd)
                }
            }
        }

        // パスポートに住所欄は無いので空のまま
        return info.name.isEmpty && info.dateOfBirth.isEmpty ? nil : info
    }

    // MARK: - ヘルパー

    /// 既知のラベル候補のいずれかに一致するか
    private static func looksLikeLabel(_ line: String) -> Bool {
        let labels = ["氏名", "住所", "生年月日", "性別", "有効期限", "本籍",
                      "Name", "Address", "Date of birth", "Sex", "Nationality"]
        return labels.contains { line.contains($0) }
    }

    /// 単語境界を考慮したラベル一致（"Address" が "Mailing Address" の一部としてもヒット）
    private static func containsLabel(_ line: String, label: String) -> Bool {
        line.range(of: label, options: [.caseInsensitive]) != nil
    }

    private static func extractAfterLabel(line: String, label: String) -> String? {
        guard let range = line.range(of: label) else { return nil }
        let after = String(line[range.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: ":： \t"))
        return after.isEmpty ? nil : after
    }

    private static func extractAfterLabel(line: String, labels: [String]) -> String? {
        for label in labels {
            if let result = extractAfterLabel(line: line, label: label) {
                return result
            }
        }
        return nil
    }

    /// 名前らしい行を推定（ラベル検出失敗時のフォールバック）
    /// 戦術:
    /// - 漢字+ひらがな+カタカナで構成され、長さが2-15文字
    /// - 数字・記号を含まない
    /// - 既知ラベル語を含まない
    /// - 行頭近く（最初の5行以内）にあるものを優先
    private static func guessNameLine(lines: [String]) -> String {
        let nameCharSet = CharacterSet(charactersIn:
            "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんがぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽぁぃぅぇぉっゃゅょアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲンガギグゲゴザジズゼゾダヂヅデドバビブベボパピプペポァィゥェォッャュョー 　")

        for (idx, line) in lines.prefix(7).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 && trimmed.count <= 15 else { continue }
            if looksLikeLabel(trimmed) { continue }
            // 数字を含む行は除外
            if trimmed.contains(where: { $0.isNumber }) { continue }
            // 漢字を含むかチェック
            let hasKanji = trimmed.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(scalar.value)
            }
            // 漢字 or ひらがな/カタカナのみで構成されている
            let isJapaneseOnly = trimmed.unicodeScalars.allSatisfy { scalar in
                (0x4E00...0x9FFF).contains(scalar.value) || // CJK
                nameCharSet.contains(scalar)
            }
            if hasKanji && isJapaneseOnly {
                _ = idx
                return trimmed
            }
        }
        return ""
    }

    /// 和暦・西暦の日付文字列を抽出
    static func extractDate(from text: String) -> String? {
        // 西暦: 1990年01月01日 or 1990.01.01 or 1990/01/01 or 1990-01-01
        let seirekiPattern = #"(19|20)\d{2}[年./\-]\d{1,2}[月./\-]\d{1,2}日?"#
        // 和暦: 昭和65年1月1日 / 平成31年 / 令和5年
        let warekiPattern = #"(明治|大正|昭和|平成|令和)\d{1,2}年\d{1,2}月\d{1,2}日"#
        // 英語: DD MMM YYYY (e.g., "01 JAN 1990") - パスポート風
        let englishPattern = #"\d{1,2}\s+(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\s+(19|20)\d{2}"#

        for pattern in [seirekiPattern, warekiPattern, englishPattern] {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return String(text[range])
            }
        }
        return nil
    }

    enum OCRError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "画像を処理できませんでした" }
    }
}

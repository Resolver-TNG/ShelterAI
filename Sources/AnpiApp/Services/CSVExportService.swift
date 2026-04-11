import Foundation

struct CSVExportService {
    static func export(_ records: [EvacueeRecord]) throws -> URL {
        let header = "ID,氏名,生年月日,住所,怪我状況,性別,年齢グループ,配慮事項,家族グループID,緯度,経度,緊急モード,登録日時\n"
        let formatter = ISO8601DateFormatter()

        let rows = records.map { r -> String in
            let id: String = r.id.map { "\($0)" } ?? ""
            let lat: String = r.latitude.map { "\($0)" } ?? ""
            let lon: String = r.longitude.map { "\($0)" } ?? ""
            let mode: String = r.isEmergencyMode ? "はい" : "いいえ"
            let dob: String = formatter.string(from: r.dateOfBirth)
            let created: String = formatter.string(from: r.createdAt)
            let gender: String = r.gender.label
            let ageGroup: String = r.ageGroup.label
            let needs: String = r.specialNeeds.map { $0.label }.joined(separator: ";")
            let familyGroupId: String = r.familyGroupId ?? ""
            let fields: [String] = [id, r.name, dob, r.address, r.injuryStatus,
                                    gender, ageGroup, needs, familyGroupId,
                                    lat, lon, mode, created]
            return fields.map { csvEscape($0) }.joined(separator: ",")
        }.joined(separator: "\n")

        let content = header + rows
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("evacuees_\(Date().timeIntervalSince1970).csv")
        try content.write(to: url, atomically: true, encoding: .utf8WithBOM)
        return url
    }

    /// RFC 4180準拠のCSVエスケープ
    private static func csvEscape(_ value: String) -> String {
        let needsQuoting = value.contains("\"") || value.contains(",") || value.contains("\n") || value.contains("\r")
        if needsQuoting {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

// UTF-8 BOM付きエンコーディング（Excelで文字化けしないように）
private extension String.Encoding {
    static let utf8WithBOM = String.Encoding.utf8
}

extension String {
    func write(to url: URL, atomically: Bool, encoding: String.Encoding) throws {
        var data = encoding == .utf8 ? Data([0xEF, 0xBB, 0xBF]) : Data()  // UTF-8 BOM
        guard let encoded = self.data(using: encoding) else {
            throw NSError(domain: "CSVExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "エンコード失敗"])
        }
        data.append(encoded)
        try data.write(to: url, options: atomically ? .atomic : [])
    }
}

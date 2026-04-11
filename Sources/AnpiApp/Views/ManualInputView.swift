import SwiftUI

enum InputMode {
    case selection   // カード読み取り or 手動入力の選択
    case scanning    // カメラ撮影
    case analyzing   // Gemma 4 解析中
    case reviewing   // 結果確認
    case manual      // 手動入力フォーム
}

struct ManualInputView: View {
    let isEmergencyMode: Bool
    @EnvironmentObject var db: DatabaseService
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var rateLimit: RateLimitService
    @Environment(\.dismiss) private var dismiss

    // 入力フィールド
    @State private var name = ""
    @State private var dateOfBirth = Date()
    @State private var address = ""
    @State private var injuryStatus = "なし"
    @State private var injuryLocations: Set<String> = []
    @State private var gender: Gender = .unspecified
    @State private var ageGroup: AgeGroup = .adult
    @State private var selectedNeeds: Set<SpecialNeed> = []

    // 家族グループ
    @State private var familyCandidates: [EvacueeRecord] = []
    @State private var resolvedFamilyGroupId: String? = nil
    @State private var familyGroupResolved = false  // バナー応答済み

    // Gemma 4
    @State private var capturedImage: UIImage? = nil
    @State private var detectedCardType: CardType = .other
    @State private var analysisConfidence: Float = 0.0

    // フロー制御
    @State private var inputMode: InputMode = .selection
    @State private var saved = false
    @State private var showConsent = false

    private let injuryOptions = ["なし", "軽傷", "中程度", "重傷", "不明"]
    private let bodyParts = ["頭部", "顔面", "首", "肩", "胸部", "腹部", "背中", "腰", "左腕", "右腕", "左手", "右手", "左脚", "右脚", "全身"]

    var body: some View {
        Group {
            switch inputMode {
            case .selection:
                selectionView
            case .scanning:
                CardScanView(
                    onResult: { image in
                        // 常に解析画面へ遷移（Gemma/OCR両方対応）
                        capturedImage = image
                        inputMode = .analyzing
                    },
                    onResultOCR: { info in
                        // Vision OCR直接結果（レガシーパス）
                        applyOCRResult(info)
                        inputMode = .reviewing
                    },
                    onSkip: {
                        inputMode = .manual
                    }
                )
            case .analyzing:
                if let image = capturedImage {
                    CardAnalysisView(
                        cardImage: image,
                        onComplete: { result in
                            applyGemmaResult(result)
                            inputMode = .reviewing
                        },
                        onFallback: {
                            // Vision OCRフォールバック
                            Task {
                                if let image = capturedImage,
                                   let info = try? await CardOCRService.recognize(image: image) {
                                    await MainActor.run {
                                        applyOCRResult(info)
                                        inputMode = .reviewing
                                    }
                                } else {
                                    await MainActor.run { inputMode = .manual }
                                }
                            }
                        }
                    )
                } else {
                    ProgressView("解析中...")
                }
            case .reviewing:
                CardScanResultView(
                    name: $name,
                    address: $address,
                    dateOfBirthText: Binding(
                        get: { formatDate(dateOfBirth) },
                        set: { dateOfBirth = parseDate($0) ?? dateOfBirth }
                    ),
                    cardType: detectedCardType,
                    confidence: analysisConfidence,
                    onConfirm: {
                        inputMode = .manual
                    },
                    onRetry: {
                        inputMode = .scanning
                    }
                )
            case .manual:
                formView
            }
        }
        .navigationTitle(isEmergencyMode ? "🚨 避難者登録" : "🔧 テスト登録")
        .sheet(isPresented: $showConsent) {
            ConsentView(
                onConsent: { showConsent = false; trySave() },
                onCancel: { showConsent = false; audio.stop() }
            )
        }
        .alert("保存しました", isPresented: $saved) {
            Button("続けて登録") { reset() }
            Button("一覧へ") { dismiss() }
        }
    }

    // MARK: - 入力方法選択画面

    private var selectionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("情報の入力方法を選択")
                .font(.title2).bold()

            VStack(spacing: 16) {
                // カード読み取りボタン
                Button {
                    inputMode = .scanning
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("カードを撮影して自動入力").bold()
                            Text("マイナカード・在留カード・免許証など")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                // 手動入力ボタン
                Button {
                    inputMode = .manual
                } label: {
                    HStack {
                        Image(systemName: "keyboard.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("手動で入力").bold()
                            Text("カードがない場合・読み取り失敗時")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .buttonStyle(.bordered)
                .tint(.gray)
            }
            .padding(.horizontal)

            if rateLimit.isBlocked {
                Label("しばらくお待ちください（\(rateLimit.remainingCooldown)秒）", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Spacer()
        }
    }

    // MARK: - 入力フォーム

    private var formView: some View {
        Form {
            if rateLimit.isBlocked {
                Section {
                    HStack {
                        Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
                        Text("しばらくお待ちください（\(rateLimit.remainingCooldown)秒）")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("基本情報") {
                TextField("氏名（必須）", text: $name)
                DatePicker("生年月日", selection: $dateOfBirth, displayedComponents: .date)
                TextField("住所", text: $address)
            }

            Section("怪我状況") {
                Picker("状況", selection: $injuryStatus) {
                    ForEach(injuryOptions, id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)

                if injuryStatus != "なし" && injuryStatus != "不明" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("怪我の部位（複数選択可）")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 8) {
                            ForEach(bodyParts, id: \.self) { part in
                                Button {
                                    if injuryLocations.contains(part) {
                                        injuryLocations.remove(part)
                                    } else {
                                        injuryLocations.insert(part)
                                    }
                                } label: {
                                    Text(part)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            injuryLocations.contains(part)
                                                ? Color.red.opacity(0.2)
                                                : Color.gray.opacity(0.1)
                                        )
                                        .foregroundStyle(injuryLocations.contains(part) ? .red : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Section("性別（任意）") {
                Picker("性別", selection: $gender) {
                    ForEach(Gender.allCases, id: \.self) { g in
                        Text(g.label).tag(g)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("年齢グループ") {
                Picker("年齢グループ", selection: $ageGroup) {
                    ForEach(AgeGroup.allCases, id: \.self) { ag in
                        Text(ag.label).tag(ag)
                    }
                }
            }

            Section("配慮事項（複数選択可）") {
                ForEach(SpecialNeed.allCases, id: \.self) { need in
                    Toggle(need.label, isOn: Binding(
                        get: { selectedNeeds.contains(need) },
                        set: { on in
                            if on { selectedNeeds.insert(need) }
                            else { selectedNeeds.remove(need) }
                        }
                    ))
                }
            }

            // 家族グループ候補バナー
            if !familyCandidates.isEmpty && !familyGroupResolved {
                Section {
                    FamilyGroupBanner(
                        candidates: familyCandidates,
                        onJoin: { candidate in
                            if let gid = candidate.familyGroupId {
                                resolvedFamilyGroupId = gid
                            } else {
                                // 候補者に新規グループIDを付与
                                let newId = UUID().uuidString
                                resolvedFamilyGroupId = newId
                            }
                            familyGroupResolved = true
                        },
                        onSeparate: {
                            resolvedFamilyGroupId = nil
                            familyGroupResolved = true
                        }
                    )
                }
            }

            Section {
                Button("撮り直す") { inputMode = .scanning }
                    .foregroundStyle(.blue)
            }

            Section {
                Button("登録する") {
                    lookupFamilyCandidates()
                    showConsent = true
                }
                .disabled(name.isEmpty || rateLimit.isBlocked)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - ロジック

    private func applyOCRResult(_ info: CardOCRService.CardInfo) {
        name = info.name
        address = info.address
        if let date = parseDate(info.dateOfBirth) {
            dateOfBirth = date
        }
        detectedCardType = .other
        analysisConfidence = 0.6
    }

    private func applyGemmaResult(_ result: CardAnalysisResult) {
        name = result.name
        address = result.address
        if let date = parseDate(result.dateOfBirth) {
            dateOfBirth = date
        }
        detectedCardType = result.cardType
        analysisConfidence = result.confidence
    }

    private func lookupFamilyCandidates() {
        guard !name.isEmpty, !address.isEmpty else { return }
        let fn = AddressNormalizer.extractFamilyName(name)
        let ab = AddressNormalizer.normalize(address)
        guard !fn.isEmpty, !ab.isEmpty else { return }
        familyCandidates = (try? db.findFamilyCandidates(familyName: fn, addressBlock: ab)) ?? []
    }

    private func trySave() {
        guard rateLimit.requestRegistration() else {
            audio.announceRateLimit()
            return
        }
        let fn = AddressNormalizer.extractFamilyName(name)
        let ab = AddressNormalizer.normalize(address)
        var record = EvacueeRecord(
            name: name, dateOfBirth: dateOfBirth, address: address,
            injuryStatus: injuryStatus,
            latitude: location.latitude, longitude: location.longitude,
            isEmergencyMode: isEmergencyMode, createdAt: Date()
        )
        record.familyName = fn
        record.addressBlock = ab
        record.gender = gender
        record.ageGroup = ageGroup
        record.specialNeeds = Array(selectedNeeds)
        record.familyGroupId = resolvedFamilyGroupId
        record.cardType = detectedCardType.rawValue
        // 怪我部位は「なし/不明」のときは保存しない（UIでも非表示）
        if injuryStatus != "なし" && injuryStatus != "不明" {
            record.injuryLocations = Array(injuryLocations).sorted()
        } else {
            record.injuryLocations = []
        }
        try? db.save(&record)
        audio.announceComplete(name: name)
        saved = true
    }

    private func reset() {
        name = ""; address = ""; injuryStatus = "なし"
        dateOfBirth = Date()
        gender = .unspecified
        ageGroup = .adult
        selectedNeeds = []
        familyCandidates = []
        resolvedFamilyGroupId = nil
        familyGroupResolved = false
        capturedImage = nil
        detectedCardType = .other
        analysisConfidence = 0.0
        inputMode = .selection
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年MM月dd日"
        return f.string(from: date)
    }

    private func parseDate(_ text: String) -> Date? {
        // "YYYY年MM月DD日" 形式
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        for fmt in ["yyyy年MM月dd日", "yyyy/MM/dd", "yyyy.MM.dd", "yyyyMMdd"] {
            f.dateFormat = fmt
            if let d = f.date(from: text) { return d }
        }
        return nil
    }
}

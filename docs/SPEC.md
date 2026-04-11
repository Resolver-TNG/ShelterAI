# AnpiApp — 安否確認アプリ 設計・仕様書

**バージョン**: v0.4.0  
**作成日**: 2026-04-11  
**更新日**: 2026-04-12  
**ステータス**: Phase 1-2 実装完了・Phase 3（Gemma 4 マルチモーダル）設計中  
**開発体制**: Resolver-TNG（企画/設計/実装）+ AI Assistants（共同設計/コード生成支援）

---

## 1. コンセプト

**「iPhone 1台で完結する、完全オフライン・Gemma 4 AI統合型 災害安否記録アプリ」**

- **あらゆる身分証をカメラで撮影 → Gemma 4がリアルタイム解析 → 氏名/住所/生年月日を自動抽出**
  - 対応: マイナンバーカード・運転免許証・パスポート・在留カード・健康保険証・その他
  - Gemma 4 E2B（CoreML）がデバイス上でマルチモーダル推論 → 完全オフライン
- 女性・子供への配慮情報（生理用品 / 乳幼児）を安否登録と紐づけて記録
- 住所×名字による自動家族グループ候補提示（スタッフ確認式）
- 多言語対応: Gemma 4が多言語カード・外国人避難者にも対応（Phase 3）
- **完全オフライン動作**（ネット不要・個人情報が端末外に出ない）
- CSV / PDF で出力 → 市役所・自衛隊に即引き渡し
- **無料・個人名義・App Store配布予定**
- **Gemma 4 Good Hackathon 提出作品**（締切: 2026-05-18）

### 背景

デジタル庁実証データ：マイナカード活用で避難所入所手続きが **90%短縮（9秒/人）** 実証済み。  
既存競合（ポケットサイン防災等）は有償・ネット必要・専用端末。  
本アプリは誰でもApp Storeからインストールできる無料代替。さらにGemma 4によるAI解析で**あらゆる身分証**に対応し、外国人避難者・PINを忘れた高齢者・カードを複数持つ人を全員カバーする。

---

## 2. ターゲット

- 避難所の受付担当者（1人でも運用可能）
- 自治体の防災担当
- 災害ボランティア

---

## 3. システム要件

| 項目 | 値 |
|---|---|
| iOS最小バージョン | iOS 18.0（CoreML MLState API必須）|
| 推奨デバイス | iPhone 14 Pro以降（A16以上・Neural Engine対応）|
| ストレージ | アプリ本体 〜50MB + Gemma 4モデル 〜2.7GB |
| ネットワーク | 不要（完全オフライン・モデルは初回DLのみ）|
| 権限 | カメラ、位置情報、マイク（TTS）|

### Gemma 4 モデル構成

| ファイル | サイズ | 役割 |
|---|---|---|
| `vision.mlpackage` | 322MB | 画像エンコーダ（SigLIP-base）|
| `model.mlpackage` | 2.4GB | テキストデコーダ（Int4量子化）|

ソース: `mlboydaisuke/gemma-4-E2B-coreml`（HuggingFace）  
変換元: `google/gemma-4-E2B-it`

---

## 4. 起動モード

```
┌─────────────────────────┐
│  🚨 緊急事態モード        │  ← 赤・大きく
│  (データは永続保存)       │
├─────────────────────────┤
│  🔧 テスト起動            │  ← グレー・小さく
│  (アプリ終了時に自動削除) │
└─────────────────────────┘
```

---

## 5. 画面遷移フロー（v0.4.0）

```
[ModelSetupView] ← 初回起動時のみ
  Gemma 4モデル未ダウンロードの場合に表示
  「モデルをダウンロード（2.7GB）」or「後で設定」
    ↓
[LaunchModeView] 起動モード選択
    │
    ├─ 緊急事態モード / テスト起動
    │
    ▼
[EvacueeListView] 避難者一覧（トップ）
    │
    ├─ 「登録」ボタン
    │       ▼
    │   [ConsentView] 本人同意確認
    │       │
    │       └─ 同意する
    │               ▼
    │           [CardScanView] カメラ撮影
    │               │ （ガイドフレームにカードを合わせてシャッター）
    │               │
    │               ├─ 撮影成功
    │               │       ▼
    │               │   [CardAnalysisView] ★Gemma 4 解析中
    │               │       「AIが読み取り中...」スピナー
    │               │       ↓（解析完了）
    │               │   [CardScanResultView] 解析結果確認・補正
    │               │       - 氏名 / 住所 / 生年月日 / カード種別
    │               │       - 各フィールドを手動補正可能
    │               │       ↓ 確認
    │               │   [ManualInputView] 詳細入力
    │               │       - 怪我状況 / 性別 / 年齢グループ / 配慮事項
    │               │       - [FamilyGroupBanner] 家族候補提示
    │               │       ↓ 登録
    │               │   → 一覧に戻る
    │               │
    │               └─ スキップ（手動入力）
    │                       ▼
    │                   [ManualInputView] 全フィールド手動入力
    │
    ├─ フィルターボタン → [FilterView]
    ├─ CSV出力 → [ExportView]
    └─ 避難者タップ → [EvacueeDetailView]
```

---

## 6. Gemma 4 統合仕様

### 6-1. GemmaService アーキテクチャ

```swift
// CoreMLモデルを2段階でロード
// 1. VisionEncoder: vision.mlpackage（SigLIP）
// 2. TextDecoder: model.mlpackage（Int4量子化、MLState）

final class GemmaService: ObservableObject {
    @Published var isModelLoaded: Bool
    @Published var isLoading: Bool
    
    func loadModel(visionPath: URL, modelPath: URL) async throws
    func analyzeCard(image: UIImage) async throws -> CardAnalysisResult
}

struct CardAnalysisResult {
    var cardType: CardType      // マイナカード/免許証/パスポート/在留カード/保険証/その他
    var name: String
    var address: String
    var dateOfBirth: String
    var confidence: Float       // 0.0〜1.0（確信度）
    var rawResponse: String     // Gemmaの生レスポンス（デバッグ用）
}

enum CardType: String {
    case mynumber = "マイナンバーカード"
    case driverLicense = "運転免許証"
    case passport = "パスポート"
    case residenceCard = "在留カード"
    case healthInsurance = "健康保険証"
    case other = "その他"
}
```

### 6-2. カード解析プロンプト

```
<image>
このカードから以下の情報を抽出してください。
必ずJSON形式で返してください。

{
  "card_type": "マイナンバーカード|運転免許証|パスポート|在留カード|健康保険証|その他",
  "name": "氏名（読み取れない場合は空文字）",
  "address": "住所（読み取れない場合は空文字）",
  "date_of_birth": "生年月日（YYYY年MM月DD日形式。読み取れない場合は空文字）",
  "confidence": 0.0から1.0の数値
}

注意: 個人情報は抽出のみ行い、外部送信はしません。
```

### 6-3. モデル管理（ModelManager）

```swift
final class ModelManager: ObservableObject {
    @Published var downloadProgress: Double     // 0.0〜1.0
    @Published var modelStatus: ModelStatus
    
    enum ModelStatus {
        case notDownloaded
        case downloading(progress: Double)
        case ready
        case error(String)
    }
    
    // モデルの保存先: Documents/gemma4/
    var visionModelURL: URL
    var textModelURL: URL
    
    // 初回: HuggingFaceからDL or ローカル転送
    // デモ時: Mac→iPhone転送でパス指定も可
    func downloadModels() async throws
    func importModelFromFiles(visionURL: URL, textURL: URL) throws
}
```

### 6-4. フォールバック設計

```
Gemma 4 利用可否チェック
  ├─ モデルDL済み + iOS 18 + A16以上 → Gemma 4で解析
  ├─ モデル未DL → Vision OCR（既存CardOCRService）にフォールバック
  └─ 解析失敗 → 手動入力へ
```

---

## 7. 機能仕様（Phase 1-2 実装済み）

### 7-1. 要配慮者フィールド ✅

- `gender`: female/male/other/unspecified
- `ageGroup`: infant/child/adult/elderly
- `specialNeeds`: [sanitary/infantCare/wheelchair/other]（JSON配列）
- ManualInputViewで選択・保存

### 7-2. 家族グループ候補自動提示 ✅

- 名字×丁目レベル住所でマッチング
- FamilyGroupBannerでスタッフ確認式
- 自動書き込みしない設計

### 7-3. 避難者一覧フィルター ✅

- 女性/子供/配慮事項あり/家族グループ
- フィルターチップ + AND絞り込み

### 7-4. 詳細・編集画面 ✅

- 怪我状況・配慮事項の編集
- 家族グループメンバー表示

### 7-5. CSV出力 ✅

- RFC 4180準拠・UTF-8 BOM
- 性別/年齢グループ/配慮事項/家族グループID 含む

---

## 8. アーキテクチャ

### 技術スタック

| 機能 | 技術 |
|---|---|
| UI | SwiftUI + MVVM |
| データベース | SQLite（GRDB.swift 6.24.0+）|
| GPS | CoreLocation |
| 音声 | AVSpeechSynthesizer（TTS）|
| カメラ | AVFoundation |
| AI推論 | CoreML（Gemma 4 E2B、.mlpackage形式）|
| フォールバックOCR | Vision framework（VNRecognizeTextRequest）|
| CSV出力 | 独自実装（RFC 4180準拠）|

### ファイル構成（全体）

```
anpi-app/
├── project.yml
├── Package.swift
├── Resources/
│   ├── Info.plist
│   └── AnpiApp.entitlements
└── Sources/AnpiApp/
    ├── App/
    │   └── AnpiAppApp.swift
    ├── Models/
    │   ├── EvacueeRecord.swift        ← Gender/AgeGroup/SpecialNeed/FamilyGroup
    │   └── CardAnalysisResult.swift   ← ★新規 Gemma解析結果
    ├── Services/
    │   ├── DatabaseService.swift
    │   ├── LocationService.swift
    │   ├── AudioService.swift
    │   ├── CSVExportService.swift
    │   ├── RateLimitService.swift
    │   ├── AddressNormalizer.swift
    │   ├── FamilyGroupService.swift
    │   ├── CardOCRService.swift       ← フォールバック用（既存）
    │   ├── GemmaService.swift         ← ★新規 CoreML推論
    │   └── ModelManager.swift         ← ★新規 モデルDL・管理
    └── Views/
        ├── LaunchModeView.swift
        ├── ConsentView.swift
        ├── CardScanView.swift          ← Gemma/OCR切り替え対応に更新
        ├── CardAnalysisView.swift      ← ★新規 解析中スピナー
        ├── CardScanResultView.swift    ← cardType表示追加
        ├── ManualInputView.swift
        ├── FamilyGroupBanner.swift
        ├── EvacueeListView.swift
        ├── FilterView.swift
        ├── EvacueeDetailView.swift
        ├── ExportView.swift
        ├── ModelSetupView.swift        ← ★新規 初回モデル設定
        ├── DistributionListView.swift
        └── DistributionCheckView.swift
```

---

## 9. データモデル

```swift
struct EvacueeRecord {
    var id: Int64?
    var name: String
    var familyName: String
    var dateOfBirth: Date
    var address: String
    var addressBlock: String
    var injuryStatus: String
    var gender: Gender
    var ageGroup: AgeGroup
    var specialNeedsJSON: String
    var familyGroupId: String?
    var cardType: String           // ← 新規追加: Gemmaが判定したカード種別
    var latitude: Double?
    var longitude: Double?
    var isEmergencyMode: Bool
    var createdAt: Date
}
```

---

## 10. 開発フェーズ

### Phase 1 ✅（2026-04-11完了）
- SwiftUI基本構造・GRDB・GPS・TTS・CSV・レート制限

### Phase 2 ✅（2026-04-12完了）
- 要配慮者フィールド・家族グループ・フィルター・詳細画面・CSV拡張

### Phase 3 — Gemma 4 統合（現在）

| # | タスク | Issue | 依存 |
|---|---|---|---|
| 8 | GemmaService実装（CoreML推論） | #8 | — |
| 9 | ModelManager実装（モデル管理・DL） | #9 | — |
| 10 | ModelSetupView実装（初回セットアップUI） | #10 | #9 |
| 11 | CardAnalysisView実装（解析中UI） | #11 | #8 |
| 12 | CardScanView更新（Gemma/OCR切り替え） | #12 | #8, #11 |
| 13 | CardScanResultView更新（cardType表示） | #13 | #8 |
| 14 | DBマイグレーション v4（cardTypeカラム追加） | #14 | — |
| 15 | ManualInputView更新（GemmaService連携） | #15 | #12 |
| 16 | フォールバック統合テスト | #16 | #12, #13, #15 |

### Phase 4 — 将来
- 多言語UI（英語・中国語等）
- Gemma 4による怪我状況自動補足（カメラ→怪我写真解析）
- PDF出力（避難者名簿フォーマット）
- App Store申請

---

## 11. 競合との差別化

| 項目 | ポケットサイン防災 | **ShelterAI** |
|---|---|---|
| コスト | 自治体契約・有償 | **無料・App Store** |
| インフラ | ネット必要・専用端末 | **iPhone 1台・完全オフライン** |
| 対応カード | マイナカードのみ | **全身分証（Gemma 4 AI解析）** |
| 外国人対応 | 限定的 | **在留カード・多言語対応** |
| 要配慮者対応 | 限定的 | **女性・子供・配慮事項を構造化記録** |
| 家族グループ | なし | **住所×名字で自動候補・確認式** |
| AI | なし | **Gemma 4 E2B オンデバイス推論** |
| 個人情報 | クラウド送信 | **端末内完結・外部送信ゼロ** |

---

## 12. Gemma 4 Good Hackathon 提出方針

- **テーマ**: 災害時避難所運営の効率化 × Gemma 4 オンデバイスAI
- **差別化ポイント**: 
  1. 命に関わるデータが端末外に出ない（プライバシー）
  2. 完全オフライン（災害時はネットが繋がらない）
  3. あらゆる身分証に対応（包摂性）
- **デモシナリオ**: 避難所でボランティアがiPhoneでカードを撮影→3秒でデータ登録

---

## 13. ビルド手順

```bash
cd ShelterAI
xcodegen generate
open AnpiApp.xcodeproj
# iPhone 17 Pro（シミュレータ）でRun
# Gemma 4テスト時は実機（iPhone 14 Pro以降）が必要
```

---

*設計: Resolver-TNG / AI Assistants*  
*実装・デバッグ: Resolver-TNG + AI Assistants*

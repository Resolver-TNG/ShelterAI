# AnpiApp — AIアシスタント機能 実装仕様書

**作成:** 2026-05-14
**対象:** Opus 4.7 サブエージェント実装用
**締切:** 5/18（残4日）
**ブランチ:** `feature/ai-assistant`

---

## 1. 概要

AnpiAppにTabView化されたメインUIと、2つの新画面を追加する:
- **SituationView（状況ダッシュボード）** — 登録データからの集計表示 + 物資算出
- **AIAssistantView（ローカルAI会話）** — Gemma 4とのオンデバイスチャット

---

## 2. UI遷移図（Before → After）

### Before（現在）
```
AnpiAppApp.body
  │
  ├─ [modelSetupDone == false]
  │   └─ ModelSetupView
  │        ├─ onComplete → modelSetupDone = true
  │        └─ onSkip → modelSetupDone = true
  │
  └─ [modelSetupDone == true]
      └─ LaunchModeView ─────────────────────────────────
           │                                              │
           ├─ 「緊急事態モード」ボタン                      │
           │   └─ NavigationDestination                   │
           │       └─ ManualInputView(isEmergency: true)  │
           │            ├─ .selection → 入力方法選択        │
           │            │   ├─ 「カード撮影」               │
           │            │   │   └─ .scanning               │
           │            │   └─ 「手動入力」                 │
           │            │       └─ .manual                 │
           │            ├─ .scanning → CardScanView        │
           │            │   ├─ onResult(image)             │
           │            │   │   └─ .analyzing              │
           │            │   ├─ onResultOCR(info)           │
           │            │   │   └─ .reviewing              │
           │            │   └─ onSkip                      │
           │            │       └─ .manual                 │
           │            ├─ .analyzing → CardAnalysisView   │
           │            │   ├─ onComplete(result)          │
           │            │   │   └─ .reviewing              │
           │            │   └─ onFallback                  │
           │            │       └─ .reviewing or .manual   │
           │            ├─ .reviewing → CardScanResultView │
           │            │   ├─ onConfirm → .manual (フォーム)│
           │            │   └─ onRetry → .scanning         │
           │            └─ .manual → Form                  │
           │                 ├─ 「登録する」→ ConsentView   │
           │                 │   └─ → save → alert         │
           │                 └─ 「撮り直す」→ .scanning     │
           │
           ├─ 「テストモード」ボタン                         │
           │   └─ ManualInputView(isEmergency: false)      │
           │        └─ (同上のフロー)                       │
           │                                               │
           ├─ 「一覧」ボタン (totalCount > 0)               │
           │   └─ EvacueeListView                          │
           │        ├─ → EvacueeDetailView                 │
           │        ├─ → ExportView (CSV出力)              │
           │        ├─ → FilterView (sheet)                │
           │        └─ → HelpView (sheet)                  │
           │                                               │
           └─ 「配布管理」ボタン (totalCount > 0)            │
               └─ DistributionListView                     │
                    └─ → DistributionCheckView             │
```

### After（実装後）
```
AnpiAppApp.body
  │
  ├─ [modelSetupDone == false]
  │   └─ ModelSetupView（変更なし）
  │
  └─ [modelSetupDone == true]
      └─ LaunchModeView（変更箇所: ボタン押下後の遷移先）
           │
           ├─ 「緊急事態モード」ボタン
           │   └─ NavigationDestination
           │       └─ MainTabView(isEmergencyMode: true) ← 🆕
           │
           └─ 「テストモード」ボタン
               └─ NavigationDestination
                   └─ MainTabView(isEmergencyMode: false) ← 🆕


MainTabView ← 🆕 TabView
  │
  ├─ Tab 0: 📋 記録
  │   └─ NavigationStack
  │       └─ RegistrationHomeView ← 🆕（ManualInputViewの入力選択+一覧を統合）
  │            │
  │            ├─ 「新規登録」ボタン
  │            │   └─ ManualInputView(isEmergencyMode) ← 既存（変更なし）
  │            │        └─ (既存フロー: selection → scanning → analyzing → reviewing → manual → save)
  │            │
  │            ├─ 避難者一覧（inline）
  │            │   └─ → EvacueeDetailView
  │            │
  │            ├─ toolbar: フィルター / CSV出力 / ヘルプ
  │            │   ├─ → FilterView (sheet)
  │            │   ├─ → ExportView
  │            │   └─ → HelpView (sheet)
  │            │
  │            └─ toolbar: 配布管理
  │                └─ → DistributionListView
  │                     └─ → DistributionCheckView
  │
  ├─ Tab 1: 📊 状況
  │   └─ NavigationStack
  │       └─ SituationView ← 🆕
  │            │
  │            ├─ Section: 人数サマリー
  │            │   └─ 合計 / 年齢グループ別内訳（infant/child/adult/elderly）
  │            │
  │            ├─ Section: 怪我状況
  │            │   └─ なし / 軽傷 / 中程度 / 重傷 / 不明（件数+バー）
  │            │
  │            ├─ Section: 配慮事項
  │            │   └─ SpecialNeed別の件数
  │            │
  │            ├─ Section: 性別分布
  │            │   └─ 女性 / 男性 / その他 / 未回答
  │            │
  │            └─ Section: 📦 必要物資概算
  │                └─ ShelterAnalytics.estimateSupplies() の結果表示
  │                    ├─ 飲料水: N L（3L/人/日）
  │                    ├─ 食料: N 食（3食/人/日）
  │                    ├─ 毛布: N 枚（1枚/人）
  │                    ├─ おむつ: N 枚（乳幼児×5枚/日）
  │                    ├─ 粉ミルク: N 缶（乳幼児×1缶/日）
  │                    ├─ 生理用品: N パック（女性(15-50歳想定)×1/日）
  │                    ├─ 医薬品セット: N 人分（怪我人数）
  │                    └─ 日数スライダー（1-7日、デフォルト3日）
  │
  └─ Tab 2: 🤖 AI
      └─ NavigationStack
          └─ AIAssistantView ← 🆕
               │
               ├─ [Gemmaモデル未ロード時]
               │   └─ 「AIモデルを読み込む」ボタン
               │       └─ gemma.loadModel()
               │
               ├─ [Gemmaモデルロード済み]
               │   │
               │   ├─ プリセット質問ボタン群（ScrollView horizontal）
               │   │   ├─ 💊「怪我人の対応優先度は？」
               │   │   ├─ 📦「必要物資を見積もって」
               │   │   ├─ 🍼「要配慮者をまとめて」
               │   │   ├─ 📋「現状を要約して」
               │   │   └─ 🌏「外国人避難者の状況は？」
               │   │
               │   ├─ チャットメッセージ一覧（ScrollView vertical）
               │   │   ├─ ChatBubble(role: .assistant, text: "...")
               │   │   └─ ChatBubble(role: .user, text: "...")
               │   │
               │   └─ 入力エリア（HStack）
               │       ├─ TextField("質問を入力...")
               │       └─ Button(送信) → sendMessage()
               │
               └─ sendMessage() フロー:
                   1. ShelterAnalytics.generateContext(db) → 集計テキスト
                   2. システムプロンプト + コンテキスト + ユーザー質問
                   3. gemma.chat(prompt:) → ストリーミング応答
                   4. ChatMessage追加（メモリ内、永続化不要）
```

---

## 3. 新規ファイル一覧

| # | ファイル | 種別 | 説明 |
|---|---|---|---|
| 1 | `Views/MainTabView.swift` | 🆕 View | TabView（記録/状況/AI）|
| 2 | `Views/RegistrationHomeView.swift` | 🆕 View | 記録タブのホーム（新規登録ボタン+一覧統合）|
| 3 | `Views/SituationView.swift` | 🆕 View | 状況ダッシュボード |
| 4 | `Views/AIAssistantView.swift` | 🆕 View | AI会話UI |
| 5 | `Models/ChatMessage.swift` | 🆕 Model | 会話メッセージモデル |
| 6 | `Services/ShelterAnalytics.swift` | 🆕 Service | 集計+物資算出+AIコンテキスト生成 |

## 4. 変更ファイル一覧

| # | ファイル | 変更内容 |
|---|---|---|
| 1 | `Views/LaunchModeView.swift` | 遷移先を ManualInputView → MainTabView に変更 |
| 2 | `Services/GemmaService.swift` | `chat(prompt:)` メソッド追加（会話用） |
| 3 | `Services/DatabaseService.swift` | 集計用クエリメソッド追加 |

---

## 5. 各ファイル詳細仕様

### 5.1 `Models/ChatMessage.swift`

```swift
import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String  // var: ストリーミング更新用
    let timestamp: Date

    enum Role {
        case user
        case assistant
        case system  // コンテキスト注入用（UI非表示）
    }
}
```

### 5.2 `Services/ShelterAnalytics.swift`

**集計ロジック:**

```swift
struct ShelterStats {
    let totalCount: Int
    let ageGroups: [AgeGroup: Int]     // infant: N, child: N, adult: N, elderly: N
    let genders: [Gender: Int]
    let injuries: [String: Int]        // "なし": N, "軽傷": N, ...
    let specialNeeds: [SpecialNeed: Int]
    let foreignResidents: Int          // cardType == "在留カード" の数
}

struct SupplyEstimate {
    let days: Int
    let water: Double          // リットル
    let meals: Int
    let blankets: Int
    let diapers: Int           // 乳幼児 × 5枚/日 × days
    let formula: Int           // 乳幼児 × 1缶/日 × days
    let sanitaryPads: Int      // SpecialNeed.sanitary人数 × 1パック/日 × days（or 女性(15-50)推定）
    let medicalKits: Int       // 怪我人数（なし以外）
}
```

**算出基準（内閣府「避難所における良好な生活環境の確保に向けた取組指針」準拠）:**
- 飲料水: 3L/人/日
- 食料: 3食/人/日
- 毛布: 1枚/人（日数不問）
- おむつ: 乳幼児 × 5枚/日
- 粉ミルク: 乳幼児 × 1缶/日
- 生理用品: `SpecialNeed.sanitary` 登録者 × 1パック/日
- 医薬品セット: 怪我ステータスが「なし」以外の人数

**AIコンテキスト生成メソッド:**

```swift
static func generateContext(db: DatabaseService) -> String
```

→ 全集計結果を自然言語テキスト化してプロンプトに注入する。例:

```
避難所の現在の状況:
- 登録者合計: 142名
- 年齢内訳: 乳幼児12名、子供23名、成人89名、高齢者18名
- 怪我状況: 軽傷8名、中程度3名、重傷1名
- 配慮事項: 車椅子3名、乳幼児ケア12名、生理用品7名
- 外国人避難者: 5名（在留カード登録）
- 3日分の必要物資概算: 飲料水426L、食料426食、毛布142枚...
```

### 5.3 `Services/GemmaService.swift` — 追加メソッド

```swift
// MARK: - Chat (AI Assistant)

/// 避難所AIアシスタント用のシステムプロンプト
static let shelterSystemPrompt: String = """
あなたは避難所の運営を支援するAIアシスタントです。
以下の避難所データに基づいて、簡潔で実用的な回答をしてください。
推測や不確実な情報には必ず「推定」と明記してください。
回答は日本語で、箇条書きを活用して読みやすくしてください。
"""

/// 会話用生成メソッド（ストリーミング対応）
/// - contextText: ShelterAnalytics.generateContext() の結果
/// - userMessage: ユーザーの質問
/// - onToken: ストリーミングコールバック（トークンごと）
func chat(
    contextText: String,
    userMessage: String,
    onToken: @escaping (String) -> Void
) async throws -> String
```

**実装方針:**
- `CoreMLLLM.stream()` が使える場合はストリーミング
- 使えない場合は `generate()` で一括生成
- maxTokens: 512（会話応答は簡潔に）

### 5.4 `Services/DatabaseService.swift` — 追加メソッド

```swift
// MARK: - Analytics

/// 全レコードの集計統計を返す
func fetchStats() throws -> ShelterStats

/// 年齢グループ別カウント
func countByAgeGroup() throws -> [AgeGroup: Int]

/// 怪我ステータス別カウント
func countByInjuryStatus() throws -> [String: Int]

/// 配慮事項別カウント（specialNeedsJSON をパースして集計）
func countBySpecialNeeds() throws -> [SpecialNeed: Int]
```

**注意:** `specialNeedsJSON` はJSON文字列なのでSQL集計不可。`fetchAll()` してSwift側でパースする。

### 5.5 `Views/MainTabView.swift`

```swift
struct MainTabView: View {
    let isEmergencyMode: Bool
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 0: 記録
            NavigationStack {
                RegistrationHomeView(isEmergencyMode: isEmergencyMode)
            }
            .tabItem {
                Label("記録", systemImage: "list.clipboard")
            }
            .tag(0)

            // Tab 1: 状況
            NavigationStack {
                SituationView()
            }
            .tabItem {
                Label("状況", systemImage: "chart.bar.fill")
            }
            .tag(1)

            // Tab 2: AI
            NavigationStack {
                AIAssistantView()
            }
            .tabItem {
                Label("AI", systemImage: "brain.head.profile")
            }
            .tag(2)
        }
        .navigationBarBackButtonHidden(true)  // LaunchModeViewに戻るのを防止
    }
}
```

### 5.6 `Views/RegistrationHomeView.swift`

**既存の EvacueeListView + 新規登録導線を統合した記録タブのホーム画面。**

構成:
- 上部: 登録件数 + 「新規登録」ボタン（大きく目立つ）
- 中央: 避難者一覧（EvacueeListView の内容をインライン化）
- toolbar: フィルター / CSV出力 / ヘルプ / 配布管理
- 新規登録ボタン → ManualInputView へ push（既存フローそのまま）

### 5.7 `Views/SituationView.swift`

**レイアウト:**
- ScrollView + LazyVStack
- 各セクションは角丸カード風（`.background(.regularMaterial, in: RoundedRectangle(...))`）
- 物資概算セクションに日数スライダー（Slider 1-7日、デフォルト3日）
- Pull to refresh（`.refreshable`）で再集計
- `.onAppear` で初回集計

### 5.8 `Views/AIAssistantView.swift`

**レイアウト:**
- 上部: プリセット質問（横スクロール）
- 中央: チャットログ（ScrollViewReader でスクロール追従）
- 下部: テキスト入力 + 送信ボタン（固定）
- Gemma未ロード時はロードボタン表示
- ストリーミング応答中は送信ボタンを無効化 + タイピングインジケーター

**プリセット質問テンプレート:**

```swift
static let presets: [(icon: String, label: String, prompt: String)] = [
    ("🩹", "怪我人の状況", "怪我人の人数と重症度を整理して、対応の優先度を教えてください。"),
    ("📦", "必要物資", "現在の避難者数から、今後3日間に必要な物資の種類と数量を見積もってください。"),
    ("⚠️", "要配慮者", "配慮が必要な方（乳幼児、高齢者、車椅子利用者など）の一覧と、必要な対応をまとめてください。"),
    ("📋", "全体サマリー", "避難所の現在の状況を、自治体への報告書として簡潔にまとめてください。"),
    ("🌏", "外国人対応", "外国人避難者の人数と、多言語対応で気をつけるべき点を教えてください。"),
]
```

---

## 6. LaunchModeView 変更差分

**変更箇所のみ:**

```swift
// Before:
.navigationDestination(isPresented: $showInput) {
    ManualInputView(isEmergencyMode: isEmergency)
}

// After:
.navigationDestination(isPresented: $showInput) {
    MainTabView(isEmergencyMode: isEmergency)
}
```

- `showList` / `showDistribution` の NavigationDestination は **削除**（MainTabView内に統合されるため）
- 登録件数バッジ・「一覧」「配布管理」ボタンも **削除**（MainTabView内に移動）
- LaunchModeView は純粋にモード選択のみの役割に

---

## 7. ビルド確認事項

- [ ] `MainTabView` が `NavigationStack` 内の `NavigationDestination` から表示される → 二重NavigationStack注意
  - **LaunchModeView は NavigationStack を持っている** → MainTabView内の各タブは独自の NavigationStack を持つ
  - `.navigationBarBackButtonHidden(true)` でLaunchModeViewへの戻りを防止
- [ ] `GemmaService` は `@EnvironmentObject` として既にApp全体に注入済み → AIAssistantViewで直接使える
- [ ] `DatabaseService` も同様
- [ ] iOS 18.0+ ターゲット（変更なし）

---

## 8. テスト観点

1. **LaunchModeView → MainTabView遷移** が両モード（緊急/テスト）で動作
2. **記録タブ**: 新規登録→カード撮影→解析→登録の既存フローが壊れていないこと
3. **状況タブ**: 0件時に「登録なし」表示、登録後にリアルタイム更新
4. **物資算出**: 日数スライダー変更で再計算
5. **AIタブ**: Gemma未ロード時のフォールバック表示
6. **AIタブ**: プリセット質問でコンテキスト注入+応答生成
7. **AIタブ**: 自由入力での会話

---

## 9. スコープ外（Phase 2以降）

- 会話履歴のDB永続化
- マルチターン会話（現在は毎回コンテキスト再生成のシングルターン）
- 避難者個別情報へのAI問い合わせ（プライバシー考慮）
- NFC連携（CoreNFC stub済み）
- Push通知

---

*仕様は固めた。あとはOpus 4.7の仕事。— 🦊*

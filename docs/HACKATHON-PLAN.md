# ShelterAI — Gemma 4 Good Hackathon 作戦計画

**作成:** 2026-05-12  
**締切:** 2026-05-18（日）  
**現ステータス:** Phase 3 骨格実装済み（7割）、CoreMLモデルDL済み

---

## 1. コンペ要件分析

### 提出物（全て必須）
| # | 成果物 | 内容 | 現状 |
|---|---|---|---|
| 1 | **Kaggle Writeup** | 技術的write-up（Gemma 4の活用方法詳細） | ❌ 未着手 |
| 2 | **デモ動画** | 実世界シナリオでの短尺デモ | ❌ 未着手 |
| 3 | **公開リポジトリ** | 透明性確保・コミュニティ学習用 | ⚠️ Gitea(private) → GitHub公開必要 |
| 4 | **動作するプロトタイプ** | 機能するデモ | ⚠️ Vision OCRで動作、Gemma統合が核心 |

### 審査基準（重み順）
1. **技術的実行力** — Gemma 4をどれだけ効果的に活用しているか
2. **実世界インパクト** — 具体的な問題を解決しているか
3. **コミュニケーション** — ストーリーを語れているか（動画+writeup）

### 狙うトラック（マルチエントリー可）

| トラック | 賞金 | 適合度 | 理由 |
|---|---|---|---|
| **Main Track** | $50K/25K/15K/10K | ⭐⭐⭐ | 災害×AI×プライバシーは強いストーリー |
| **Global Resilience** (Impact) | — | ⭐⭐⭐ | 災害対応そのもの |
| **Cactus** (Special Tech) | $10K | ⭐⭐⭐ | "local-first mobile app that intelligently routes tasks between models" = ShelterAIそのもの |

**Cactusトラックが最もフィットする。** 
- local-first ✅（完全オフライン）
- mobile ✅（iPhone）
- intelligently routes tasks between models ✅（Gemma 4 ↔ Vision OCRフォールバック）

---

## 2. 差別化ポイント（勝てる理由）

### 技術面
1. **CoreML + Neural Engine**: LiteRTではなくApple純正パス。iPhone上でE2B(2B effective)が動く
2. **マルチモーダル**: カメラ→SigLIP→テキストデコーダ→構造化JSON。単なるチャットボットではない
3. **インテリジェント・ルーティング**: Gemma 4 ← → Vision OCR のフォールバック設計（Cactusの要件に完全合致）
4. **実用的なプロンプト設計**: カード種別ごとの最適化（Issue #27）

### インパクト面
1. **デジタル庁実証データ**: マイナカード活用で90%短縮（9秒/人）の先行事例あり → 根拠がある
2. **完全オフライン**: 災害時はネット不通 → これが決定的な差別化
3. **プライバシー**: 個人情報が端末外に出ない → 身分証データだから超重要
4. **包摂性**: 全身分証対応（マイナカードだけでなく免許/パスポート/在留カード/保険証）→ 外国人避難者もカバー
5. **無料**: 既存競合は有償・専用端末 → App Storeから誰でもインストール

### ストーリー（審査員の心を動かすナラティブ）
> 「2024年1月1日の能登半島地震。避難所で紙とペンで名前を書いてもらう旧来の方法が未だに使われていた。
> デジタル庁の実証実験では、マイナカードを使えば90%の時間短縮が可能と証明された。
> だが実運用のハードルは高い — 有償、ネット必要、専用端末、マイナカード限定。
> ShelterAIはそのすべてを解決する。iPhone 1台、完全オフライン、あらゆる身分証に対応、無料。
> Gemma 4がデバイス上で動くからこそ実現できた。」

---

## 3. 6日間スプリント計画

### Day 1: 5/12（月）夜 ✅ → 今ここ
- [x] 環境構築（clone + Gemma 4モデルDL）
- [x] 作戦立案（本ドキュメント）
- [ ] CoreML-LLM パッケージ調査・動作確認方法整理

### Day 2: 5/13（火）
- [ ] **Issue #29 CoreML実推論統合** — 最重要
  - Package.swiftにCoreML-LLM依存追加
  - iOS最小バージョン 18.0に引き上げ
  - GemmaService.swift書き換え（CoreMLLLM.load + generate(image:)）
  - シミュレータ/実機テスト
- [ ] **Issue #27 プロンプト最適化**（#29と並行）
  - カード種別ごとの最適プロンプト設計
  - JSON出力の安定化（構造化出力）

### Day 3: 5/14（水）
- [ ] #29 デバッグ・調整
- [ ] **Issue #26 モデルDLフロー**: Bundle内蔵 vs 初回DL判断
  - ハッカソンデモ用: Bundle内蔵（確実に動く）がベスト
  - App Store用: 初回DL方式（2.7GBはApp Store審査で問題）
  - **提出時はBundle内蔵 + README「App Store版は初回DL」で可**
- [ ] フォールバック動作確認（Gemma失敗→Vision OCR）

### Day 4: 5/15（木）
- [ ] **GitHub公開リポジトリ準備**
  - Resolver-TNG/ShelterAI で公開
  - README.md（英語）: プロジェクト概要、セットアップ手順、アーキテクチャ図
  - LICENSE: Apache 2.0（コンペ要件）
  - モデルファイルは.gitignoreでHuggingFaceリンクのみ
- [ ] 統合テスト・Issue #16

### Day 5: 5/16（金）
- [ ] **デモ動画撮影**
  - シナリオ: 避難所でボランティアがiPhoneでカードを撮影→3秒登録→CSV出力
  - 実機（iPhone 14 Pro以降）で撮影
  - 60-120秒。ナレーション英語（字幕日本語）or 日本語ナレーション
  - 問題提示→ソリューション→動作デモ→インパクトの構成
- [ ] **Kaggle Writeup** ドラフト

### Day 6: 5/17（土）
- [ ] Writeup最終化・動画編集
- [ ] **Issue #30 最終ビルド確認**
- [ ] **Kaggle Submit** ⬅️ ここが〆切前日（バッファ）

### 5/18（日）= 締切日
- 最終調整・提出確認のみ

---

## 4. 提出パッケージ構成

### Kaggle Writeup 構成案
```
# ShelterAI: Offline AI-Powered Disaster Shelter Registration

## Problem
- 避難所受付の紙運用 → 9秒/人に短縮できるデジタル庁実証
- 既存解: 有償/ネット必要/マイナカード限定

## Solution  
- iPhone + Gemma 4 E2B (CoreML) = 完全オフラインAI身分証読み取り
- フォールバック: Gemma 4 → Vision OCR → 手動入力

## Technical Implementation
- CoreML-LLM + SigLIP + Int4デコーダ
- マルチモーダル推論パイプライン
- インテリジェント・ルーティング（Cactusトラック要件）
- プロンプトエンジニアリング（カード種別別）

## Impact
- デジタル庁実証: 90%時間短縮
- 完全オフライン = 災害時の現実
- プライバシー = 端末内完結
- 包摂性 = 全身分証対応

## Architecture
[図: カメラ → SigLIP → Gemma 4 → JSON → DB → CSV]

## Demo
[動画リンク]
```

### GitHub リポ構成
```
ShelterAI/
├── README.md (English)
├── LICENSE (Apache 2.0)
├── docs/
│   ├── SPEC.md
│   ├── ARCHITECTURE.md
│   └── DEMO.md
├── Sources/
├── Resources/
├── Package.swift
├── project.yml
└── .gitignore (Models/ を除外)
```

---

## 5. リスクと対策

| リスク | 影響 | 対策 |
|---|---|---|
| CoreML-LLMがiOS 18シミュレータで動かない | #29ブロック | 実機テスト必須。シミュレータはVision OCRフォールバックで代替 |
| 2.7GBモデルのApp Bundle内蔵がXcodeで問題 | デモ不可 | Documents/へコピー方式にフォールバック |
| デモ動画に実機が必要 | 撮影できない | マスターのiPhone 14 Pro or 15を使用 |
| 英語ナレーションの品質 | 審査印象 | 字幕+画面録画メイン。ナレーション最小限 |
| 5/13 CPI発表でマスター時間取られる | スケジュール | 実装はリヴァ+Kiroで自律進行 |

---

## 6. 開発体制（リヴァ移管後）

- **リヴァ（Opus）**: 作戦立案、アーキテクチャ設計、Writeup、コードレビュー
- **Kiro ACP**: CoreML統合コード生成、Swift実装の本体
- **マスター**: 実機テスト、デモ動画撮影、最終判断
- **リゾルバ**: 必要時にSwiftデバッグ支援

---

*作戦は立てた。あとは実行するだけ。— 🦊*

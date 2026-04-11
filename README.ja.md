# ShelterAI — 完全オフライン避難所管理アプリ（Gemma 4搭載）

<p align="center">
  <img src="assets/readme-banner.png" alt="ShelterAI バナー" width="100%">
</p>

<p align="center">
  <img src="assets/app-icon.png" alt="ShelterAI アイコン" width="120">
</p>

[![iOS](https://img.shields.io/badge/iOS-18.0+-blue)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-green)](LICENSE)
[![Gemma 4](https://img.shields.io/badge/Gemma%204-E2B%20CoreML-blueviolet)](https://huggingface.co/mlboydaisuke/gemma-4-E2B-coreml)
[![Hackathon](https://img.shields.io/badge/Gemma%204%20Good-Hackathon%202026-red)](https://www.kaggle.com/competitions/gemma-4-good-hackathon)

> **紙を否定しない、もう一つの選択肢。**

### 🎬 [デモ動画](https://youtu.be/s2XrPMB0DGc)

<p align="center">
  <img src="assets/screenshot-list.png" alt="避難者リスト" width="230">
  <img src="assets/screenshot-dashboard.png" alt="状況ダッシュボード" width="230">
  <img src="assets/screenshot-ai.png" alt="AIアシスタント" width="230">
</p>

ShelterAIは、完全オフラインで動作するiOS向け避難所管理アプリです。身分証にカメラをかざすだけで、Gemma 4 E2Bがデバイス上で氏名・住所・生年月日を解析し、数秒で避難者を登録します。インターネット不要、サブスクリプション不要、特別な機材不要。

**トラック:** Main | Global Resilience | Cactus (Local-First Mobile)

---

## 主な機能（30機能、6,326行）

### 📸 登録・カードスキャン
- **自動シャッターカメラ** — VNDetectRectanglesRequestによるリアルタイムカード検出、1.4秒の安定検出後に自動撮影
- **Gemma 4マルチモーダル解析** — 画像+プロンプト → 構造化JSON（氏名・住所・生年月日・カード種別）
- **Vision OCRフォールバック** — Apple Visionによるクロスチェック、信頼度ゲート付きハイブリッドマージ
- **5種類の身分証対応** — マイナンバーカード、運転免許証、パスポート（MRZ）、在留カード、健康保険証
- **手動入力** — 15部位の怪我部位ピッカー、配慮事項トグル、性別・年齢ピッカー
- **家族グループ推定** — 同姓＋同住所ブロック → 自動グループ化提案
- **同意ゲート** — 保存前に毎回プライバシー同意を取得
- **レート制限** — 1分あたり5件の登録上限
- **音声案内** — 日本語TTSによるハンズフリー確認
- **GPS記録** — 各レコードに位置情報を付与

### 🤖 AIアシスタント — インテリジェントルーティング
- **5つの定型プリセット** — 怪我人トリアージ、物資推定、要配慮者名簿、サマリー、外国人支援。Swiftコードでデータベースから生成 — **精度100%、即時応答**
- **自由質問（Gemma 4 Q&A）** — 避難所運営に関するあらゆる質問にストリーミング回答
- **会話管理** — リセットボタン、セッション単位のメモリ

> **なぜインテリジェントルーティング？** 2Bモデルは柔軟なタスク（マルチモーダル抽出・自由質問）に優れますが、構造化データの検索は苦手です。プリセットはコードへ、自由質問はAIへ。各クエリを最適なシステムに振り分けます。

### 📊 状況ダッシュボード
- **リアルタイム統計** — 年齢・性別・怪我重症度・配慮事項の内訳
- **物資推定** — 内閣府ガイドラインに基づく1〜30日スライダー（水3L/人/日、食料、毛布、おむつ、粉ミルク、衛生用品、医療キット）
- **外国人検出** — 氏名ベースのヒューリスティクス（ASCII/カタカナのみの氏名）

### 📋 データ管理
- **SQLite（GRDB）** — 5段階スキーママイグレーション
- **検索＋フィルター** — `.searchable`バー＋属性チップフィルター
- **個別削除** — 確認ダイアログ付きレコード単位削除
- **CSVエクスポート** — UTF-8 BOM（Excel対応）。オフラインで収集 → 通信復旧後にAirDrop/USB/メールで行政に引き渡し
- **物資配布管理** — 避難者ごとのチェックリスト＋進捗バー
- **サンプルデータ** — テスト・デモ用の18名の避難者データ

### 🔒 プライバシー
- コードベース全体で**ネットワーク通信ゼロ**
- アナリティクスなし、テレメトリなし、Firebaseなし
- 依存ライブラリ2つのみ（GRDB.swift、CoreML-LLM）
- テストモードのデータはアプリ終了時に自動削除

---

## アーキテクチャ

```
カメラ → CardPreprocessor → ┬─ Gemma 4 E2B (CoreML) ─┐
                             └─ Vision OCR (フォールバック) ──┤
                                                            ├→ 信頼度マージ → 登録
                                                            │
AIアシスタント ─── プリセット? ─── YES → ShelterAnalytics (Swiftコード, 100%)
                              └── NO  → Gemma 4 E2B (ストリーミング)
```

| レイヤー | 技術 |
|---|---|
| UI | SwiftUI (iOS 18), TabView, NavigationStack, .searchable |
| AI | CoreMLLLM (Gemma 4 E2B), チャンク分割CoreMLモデル |
| 画像認識 | VNRecognizeTextRequest, VNDetectRectanglesRequest, CIPerspectiveCorrection |
| カメラ | AVCaptureSession + AVCaptureVideoDataOutput (リアルタイム検出) |
| データベース | GRDB.swift (SQLite), 5マイグレーション |
| 音声 | AVSpeechSynthesizer (ja-JP) |
| 位置情報 | CoreLocation (緊急モード) |

---

## セットアップ

### 前提条件
- Xcode 16.0+ / iOS 18.0+デバイス
- 約3GBの空きディスク容量（モデルファイル用）
- Gemma 4推論にはNeural Engineが必要（シミュレータではVision OCRフォールバックのみ）

### 1. クローン＆ビルド

```bash
git clone https://github.com/Resolver-TNG/ShelterAI.git
cd ShelterAI
open AnpiApp.xcodeproj
```

### 2. Gemma 4 E2B CoreMLモデルのダウンロード

モデルファイル（約2.7GB）はリポジトリに含まれていません：

```bash
pip install huggingface_hub
python -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='mlboydaisuke/gemma-4-E2B-coreml',
    local_dir='Models/gemma-4-E2B-coreml'
)
"
```

> ダウンロード前にHugging Faceで[Gemma 4ライセンス](https://huggingface.co/mlboydaisuke/gemma-4-E2B-coreml)に同意してください。

### 3. 実行

デバイスを選択 → Development Teamを設定 → ▶ Run。SPMがGRDBとCoreML-LLMを自動解決します。初回モデルロードには10〜30秒かかります。

---

## ハッカソンコンテキスト

**コンペティション:** [Gemma 4 Good Hackathon](https://www.kaggle.com/competitions/gemma-4-good-hackathon)（締切: 2026年5月18日）

デジタル庁の実証では、デジタルID処理により避難所の受付時間が**90%短縮**されることが示されました。しかし既存のソリューションはすべて、インターネット接続・有料サブスクリプション・専用ハードウェアを必要とします。ShelterAIはGemma 4をデバイスに直接搭載することで、これらの障壁をすべて取り除きます。

500人規模の避難所で：紙ベースでは約12.5時間 → ShelterAIでは約0.8時間。**11時間以上**をケア・配布・連携に振り向けられます。

---

## なぜオープンソースか

ShelterAIはApache 2.0でリリースしています。防災はコモンズに属するべきだからです。フォークし、改変し、デプロイしてください — 許可も、稟議書も不要です。

*インターネットも、予算も、時間もない緊急時のために — Gemma 4を搭載したスマートフォンが、ボランティアのポケットに収まる唯一の追加ツールになるように。*

---

## ライセンス

[Apache License 2.0](LICENSE)。Gemma 4モデルの重みは[Gemma利用規約](https://ai.google.dev/gemma/terms)に従います。

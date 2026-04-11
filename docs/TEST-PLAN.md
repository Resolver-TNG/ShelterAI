# AnpiApp テストプラン — iPhone/iPad Pro実機テスト

**作成:** 2026-05-12  
**テスト端末:** iPhone（14 Pro以降）/ iPad Pro（M1以降）

---

## 1. テスト環境セットアップ

### 前提条件
- Xcode 16+ インストール済み（Mac）
- 開発者アカウント（Free or Paid）でデバイス登録済み
- USB-CケーブルでMac↔デバイス接続

### ビルド手順
```bash
cd ./

# xcodegen で .xcodeproj 生成（project.yml から）
xcodegen generate

# Xcode で開く
open AnpiApp.xcodeproj

# Signing: Team を自分のApple IDに設定
# Target Device: 接続したiPhone/iPad Proを選択
# Cmd+R でビルド & 実行
```

### モデル配置（実機テスト用）
```
方法A: App Bundle内蔵（確実だが重い）
  - Models/gemma-4-E2B-coreml/ をXcodeプロジェクトにドラッグ
  - Build PhasesのCopy Bundle Resourcesに追加
  - ⚠️ アプリサイズ ~2.8GB（App Store審査は別問題）

方法B: Documents/にファイル転送（開発用推奨）
  - Xcodeの Devices & Simulators → デバイス選択
  - AnpiApp の Container → Download Container
  - Documents/gemma4/ にモデルファイルをコピー → Replace Container
  - or: iTunes File Sharing経由で転送
  
方法C: 初回起動時DL（WiFi必要）
  - ModelManager.downloadModels() がHuggingFaceからDL
  - 開発中は方法Bの方が確実
```

---

## 2. テストケース一覧

### Phase 1: 基本動作確認（Vision OCRフォールバック）

| # | テスト | 期待結果 | 合否 |
|---|---|---|---|
| 1-1 | アプリ起動 → LaunchModeView表示 | 緊急/テストモード選択画面 | |
| 1-2 | テストモード → EvacueeList表示 | 空リスト + 登録ボタン | |
| 1-3 | 登録 → ConsentView → 同意 | CardScanViewに遷移 | |
| 1-4 | カメラ起動 → 撮影 | CardAnalysisViewに遷移 | |
| 1-5 | Vision OCRで氏名抽出 | CardScanResultViewに結果表示 | |
| 1-6 | 結果確認 → ManualInput → 登録 | リストに追加される | |
| 1-7 | CSV出力 | UTF-8 BOM付きCSVが生成される | |

### Phase 2: Gemma 4 CoreML推論

| # | テスト | 期待結果 | 合否 |
|---|---|---|---|
| 2-1 | ModelSetupView → モデルロード | isModelLoaded = true, 初回1-2分 | |
| 2-2 | マイナカード撮影 → Gemma解析 | 氏名+住所+生年月日がJSON抽出される | |
| 2-3 | 運転免許証 → Gemma解析 | card_type="運転免許証" + 情報抽出 | |
| 2-4 | パスポート → Gemma解析 | card_type="パスポート" + 名前抽出 | |
| 2-5 | 推論時間 | 3-5秒以内（E2B ~11 tok/s） | |
| 2-6 | メモリ使用量 | 推論中 < 3GB RAM使用 | |
| 2-7 | 不鮮明画像 → フォールバック | Vision OCRに自動切り替え | |
| 2-8 | confidence表示 | 0.0-1.0の値がResultViewに表示 | |

### Phase 3: ハイブリッド推論 & 前処理

| # | テスト | 期待結果 | 合否 |
|---|---|---|---|
| 3-1 | 斜め撮影 → 前処理補正 | CardPreprocessorが矩形検出+補正 | |
| 3-2 | 暗い画像 → コントラスト調整 | 読み取り精度がUpする | |
| 3-3 | Gemma低confidence → OCR採用 | conf < 0.5 で自動切り替え | |
| 3-4 | 両方実行 → マージ | フィールド突き合わせ結果 | |

### Phase 4: エッジケース

| # | テスト | 期待結果 | 合否 |
|---|---|---|---|
| 4-1 | 機内モード ON → 全機能動作 | ネットワークエラーなし | |
| 4-2 | カメラ権限拒否 | 適切なエラーメッセージ | |
| 4-3 | 連続10人登録 | メモリリーク/クラッシュなし | |
| 4-4 | テストモード → アプリ終了 → 再起動 | データ削除確認 | |
| 4-5 | 緊急モード → データ永続確認 | アプリ再起動後もデータあり | |

---

## 3. テスト用素材

### 身分証サンプル画像
撮影に使うテスト用カード:
- マイナカード: マスターの実物 or 総務省サンプル画像
- 運転免許証: マスターの実物
- パスポート: マスターの実物（表紙+データページ）
- 在留カード: サンプル画像（法務省公開）
- 保険証: マスターの実物

⚠️ **テスト時の個人情報注意**: デモ動画にはサンプル画像 or モザイク処理を使用

### テスト用サンプル画像ダウンロード先
```
# 総務省マイナカードサンプル
https://www.soumu.go.jp/kojinbango_card/03.html

# 法務省在留カードサンプル  
https://www.moj.go.jp/isa/applications/procedures/16-4.html
```

---

## 4. パフォーマンス計測

### 計測ポイント
| 指標 | 目標値 | 計測方法 |
|---|---|---|
| モデルロード時間 | < 120秒（初回）, < 5秒（キャッシュ後） | print(Date()) before/after |
| 推論時間（1カード） | < 5秒 | Timer in GemmaService |
| 前処理時間 | < 500ms | Timer in CardPreprocessor |
| メモリ使用量ピーク | < 3.5GB | Xcode Memory Debugger |
| バッテリー消費 | < 5%/10回登録 | Settings > Battery |

### Xcode Instruments チェック
- Allocations: メモリリークなし
- Time Profiler: ボトルネック特定
- Neural Engine: ANE使用率確認（CoreML Performance）

---

## 5. デモ動画撮影プラン

### 機材
- iPhone実機（AnpiApp実行）
- 画面録画（Settings → Control Center → Screen Recording）
- or Mac + QuickTime Player でミラーリング録画（高画質）

### シナリオ（60-90秒）
```
0:00-0:10  問題提示（テロップ: "災害時、避難所の受付は紙とペン"）
0:10-0:15  アプリ起動（緊急事態モード選択）
0:15-0:25  マイナカードをカメラで撮影
0:25-0:35  Gemma 4が解析中... → 結果表示（氏名/住所/生年月日）
0:35-0:45  確認 → 追加情報入力 → 登録完了
0:45-0:55  2人目を運転免許証で登録（スピード感）
0:55-1:05  CSV出力 → 「市役所に引き渡し可能」
1:05-1:15  機内モード表示 → 「完全オフライン動作」テロップ
1:15-1:20  エンドカード（AnpiApp + Gemma 4 + tracks）
```

### 撮影日: 5/16（金）予定
- 前日5/15に統合テスト完了 → 撮影可能状態

---

## 6. iPad Pro テスト追加事項

iPad Pro（M1以降）でもテスト可能:
- Neural Engine: M1のANEはA16以上相当 → CoreML動作OK
- 画面サイズ: SwiftUIのレイアウト崩れ確認
- Split View: 横画面でのUI確認（避難所では横置き運用あり得る）
- ⚠️ カメラ位置がiPhoneと異なる → CardScanViewのガイドフレーム確認

---

*テストは実装完了後、5/14-15で集中実施。*

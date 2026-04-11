# AnpiApp 実機テスト クイックスタート

## 前提
- Xcode 16+ インストール済み
- iPad Pro M1 を USB-C 接続、充電中でOK
- Apple ID（Free Provisioning可）

## 手順（5分）

### 1. Xcodeで開く
```bash
cd ./
open AnpiApp.xcodeproj
```

### 2. Signing 設定
- Xcode左のProject Navigator → AnpiApp (青いアイコン) → Signing & Capabilities
- Team: 自分のApple ID を選択
- Bundle ID: `jp.resolver.anpiapp` のまま（自動で変わるかも）

### 3. ターゲット選択
- Xcode上部のデバイスセレクター → 接続したiPad Pro を選択

### 4. ビルド & 実行
- Cmd+R（またはPlayボタン）
- 初回: iPad側で「デベロッパーを信頼」ダイアログが出る → 設定 > 一般 > VPNとデバイス管理 で信頼

### 5. テスト手順
1. 「後で設定する（Vision OCRで起動）」をタップ → メイン画面
2. テストモード選択 → 避難者一覧
3. 「登録」→ 同意 → カメラ起動
4. 身分証を撮影（マイナカード/免許証等）
5. OCR結果確認 → 登録

### モデル内蔵テスト（Gemma 4推論）
※ Resources/Models/ に4GBモデルが入っている場合:
- 初回起動の「モデルをダウンロード」→ Bundle内蔵パスを自動検出 → ロード
- カード撮影 → Gemma 4 が解析（3-5秒）→ JSON結果

### トラブルシューティング
- **「信頼されていないデベロッパー」**: 設定 > 一般 > VPNとデバイス管理
- **ビルドエラー「Signing requires development team」**: Team未設定
- **カメラ黒画面**: シミュレータでは不可。実機のみ
- **モデルロード失敗**: Resources/Models/gemma-4-E2B-coreml/ が存在するか確認

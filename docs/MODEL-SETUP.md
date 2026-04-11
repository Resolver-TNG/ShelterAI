# Gemma 4 E2B CoreML モデル配置仕様

## 概要

`Resources/Models/gemma-4-E2B-coreml/` 配下に必要なモデルファイル一式を配置する。
このディレクトリは `.gitignore` 対象（巨大バイナリのためVCS外）。
ビルド時に Xcode の "Copy Gemma 4 Models" Run Script Phase が `rsync -a --delete`
でアプリバンドル `<App>.app/Models/gemma-4-E2B-coreml/` へコピーする。

## 必須ファイル一覧（4-chunk + 3-chunk Topology II 両対応）

```
Resources/Models/gemma-4-E2B-coreml/
├── model_config.json                       # 必須: model_name=gemma4-e2b-swa-2k, context_length=2048
│
├── chunk1.mlmodelc/                        # SWA L0-7 own-KV (149 MB)
├── chunk2.mlmodelc/                        # SWA L8-14 own-KV (128 MB) — 4-chunk mode
├── chunk3.mlmodelc/                        # SWA L15-24 shared-KV (311 MB) — 4-chunk mode
├── chunk4.mlmodelc/                        # SWA L25-34 + LM head (503 MB) — 4-chunk mode
├── chunk2_3way.mlmodelc/                   # Topology II: L8-24 merged (439 MB)
├── chunk3_3way.mlmodelc/                   # Topology II: L25-34 + LM head (503 MB)
│
├── hf_model/
│   ├── tokenizer.json                      # 必須 (CoreML-LLM が swift-transformers 経由で読込)
│   └── tokenizer_config.json               # optional だが推奨
│
├── embed_tokens_q8.bin                     # INT8 token embeddings (402 MB)
├── embed_tokens_scales.bin
├── embed_tokens_per_layer_q8.bin           # INT8 PLE (2.19 GB)
├── embed_tokens_per_layer_scales.bin
├── embed_proj_weight.npy                   # vision/audio → text embed projection (4.5 MB)
├── per_layer_norm_weight.bin               # 1 KB
├── per_layer_projection.bin                # 27 MB (35 * 256 * 1536 * 2 bytes fp16)
├── output_proj_weight.npy                  # 3 MB
├── output_proj_bias.npy                    # 3 KB
│
├── cos_full.npy                            # 8 MB — RoPE cos table (full attn)
├── cos_sliding.npy                         # 4 MB
├── sin_full.npy                            # 8 MB
├── sin_sliding.npy                         # 16 MB
│
├── vision.mlmodelc/                        # SigLIP encoder
├── vision.ane.mlmodelc/                    # ANE-optimized vision encoder
├── vision.mlpackage/                       # uncompiled fallback
├── audio.mlmodelc/                         # Whisper-style audio encoder (282 MB)
├── audio_config.json                       # audio path config
├── mel_filterbank.bin                      # 129 KB (audio frontend)
└── (config.json, tokenizer.json, tokenizer_config.json — 旧位置の互換ファイル)
```

合計約 5.0 GB。

## chunk バリアントの選び方（重要）

CoreML-LLM の `ChunkedEngine` は **入力スキーマの揃ったセット**を要求する。
chunk1-4 が `causal_mask_full` + `causal_mask_sliding` を要求するなら、
chunk2_3way / chunk3_3way も同じスキーマでなければならない。
**異なるバリアントを混在させると `Feature causal_mask is required but not specified` エラー**。

互換性のあるセット（推奨）:
- `Models/gemma-4-E2B-coreml/swa/` 配下の chunk1-4 + chunk2_3way + chunk3_3way + cos*/sin* を
  そのまま `Resources/Models/gemma-4-E2B-coreml/` に配置する。
- このセットは **stateless SWA（KV cache を入力で受け取る）** + **causal_mask_full/sliding 2分割**
  + **2048 context** ビルド。

互換性のないセット（NG例）:
- ルート直下の `Models/gemma-4-E2B-coreml/chunk{1,2,3}.mlmodelc`（stateful 512-slot KV）
  に `stateless-ctx2048/chunk4.mlmodelc`（stateless 2048 ctx）を組み合わせる。
  → chunk1-3 は `causal_mask` 単一入力、chunk4 は `causal_mask` 単一だが KV は外部入力で
     mismatch が起こる。

## model_config.json の落とし穴

`Models/gemma-4-E2B-coreml/swa/model_config.json` は `model_name: gemma4-e2b-swa-8k`,
`context_length: 8192` と書かれているが、**実際の chunk1 の `K_full_in` shape は
`[1, 1, 2048, 512]`** で 2K context。これは HF 側の config メタデータの不整合。

ChunkedEngine は `chunk1.causal_mask_full` の最後の次元と `model_config.context_length`
を比較してバリデーションする (ChunkedEngine.swift L750)。**model_config.json の
context_length を 2048 に書き換える必要がある** (本リポでは修正済み)。

## デプロイ手順

```bash
cd ./
DST="Resources/Models/gemma-4-E2B-coreml"
SRC="Models/gemma-4-E2B-coreml"

# chunks (4-chunk + Topology II 両対応セット)
for f in chunk1 chunk2 chunk3 chunk4 chunk2_3way chunk3_3way; do
  cp -R "$SRC/swa/$f.mlmodelc" "$DST/"
done

# RoPE tables
cp "$SRC/swa/"{cos,sin}_{full,sliding}.npy "$DST/"

# model_config.json を 2K context 仕様に修正してコピー
cp "$SRC/swa/model_config.json" "$DST/model_config.json"
# 注意: copy 後に model_name="gemma4-e2b-swa-2k", context_length=2048 に手動編集する

# embed/per_layer/output_proj/hf_model/vision/audio/mel_filterbank はモデル非依存
# のため `Models/gemma-4-E2B-coreml/` 直下から流用 (既存配置を維持)
```

## ビルド確認

```bash
xcodebuild -project AnpiApp.xcodeproj -scheme AnpiApp \
  -destination 'generic/platform=iOS' -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
```

ビルド成功時は `Copying Gemma 4 model to bundle... Model copy complete (5.0G)` と
`** BUILD SUCCEEDED **` の両方が出る。

## 過去のエラーと修正履歴

1. **`tokenizer.json not found`** → `hf_model/tokenizer.json` を配置して解決
2. **`chunk4 not found`** → `stateless-ctx2048/chunk4` をコピーするも次のエラーへ
3. **`Feature causal_mask is required but not specified`** ← swa/ 統一で解決
   - chunk1-3 (swa-2k stateful, `causal_mask` 単一) と
     chunk4 (stateless-ctx2048, `causal_mask` 単一だが KV input が異なる) の混在が原因
   - 解決: swa/ 配下のフルセット (chunk1-4 + 3way) で統一、`causal_mask_full` + `causal_mask_sliding` の
     stateless 2K SWA に揃えた

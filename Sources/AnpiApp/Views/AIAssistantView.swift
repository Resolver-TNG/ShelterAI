import SwiftUI

/// AIアシスタントタブ
///
/// Gemma 4 ローカルモデルを使った避難所運営チャット。
/// プリセット質問 + 自由入力に対応。会話履歴はメモリ内のみ（セッション終了で消える）。
struct AIAssistantView: View {
    @EnvironmentObject var gemma: GemmaService
    @EnvironmentObject var db: DatabaseService

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isGenerating: Bool = false
    @State private var showError = false
    @State private var errorMsg = ""
    @State private var showResetConfirmation = false
    @FocusState private var inputFocused: Bool

    /// プリセット質問
    ///
    /// 設計方針:
    /// - データ確定型の質問(怪我人・物資・要配慮者・サマリー・外国人)は
    ///   `ShelterAnalytics.generatePresetAnswer(_:db:)` でコード生成された確定テキストを表示する。
    /// - E2B(2Bパラメータ)はセクション間の情報統合・似たラベルの区別が苦手なため、
    ///   AIではなくデータベースの集計結果をそのまま見せる方がユーザー価値が高い。
    /// - PresetKind はプリセットとコード生成メソッドを紐づけるタグ。
    /// - 自由入力の質問だけが Gemma 4 E2B に渡される。
    static let presets: [(icon: String, label: String, kind: ShelterAnalytics.PresetKind)] = [
        ("🩹", "怪我人の状況", .injuryStatus),
        ("📦", "必要物資", .supplies),
        ("⚠️", "要配慮者", .specialNeeds),
        ("📋", "全体サマリー", .overallSummary),
        ("🌏", "外国人対応", .foreignSupport),
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !gemma.isModelLoaded {
                modelLoadingPanel
            } else {
                presetBar
                Divider()
                chatLog
                Divider()
                inputBar
            }
        }
        .navigationTitle("AI アシスタント")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ExitToModeSelectionButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showResetConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(messages.isEmpty || isGenerating)
                .accessibilityLabel("会話をリセット")
            }
        }
        .confirmationDialog(
            "会話をリセットしますか？",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("リセット", role: .destructive) {
                messages.removeAll()
                inputText = ""
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("これまでの会話履歴がすべて削除されます。")
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMsg)
        }
    }

    // MARK: - Model Loading Panel

    private var modelLoadingPanel: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.purple)
            Text("AIアシスタント")
                .font(.title2).bold()
            Text("Gemma 4 オンデバイスモデルを読み込みます。\n初回ロードには時間がかかります（数十秒〜数分）。")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if gemma.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(gemma.progressStep.isEmpty ? "読み込み中..." : gemma.progressStep)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await loadModel() }
                } label: {
                    Label("AIモデルを読み込む", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .padding(.horizontal)
            }

            Text("⚠️ ネットワーク不要・データはデバイス内で完結します")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    // MARK: - Preset Bar

    private var presetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.presets, id: \.label) { preset in
                    Button {
                        guard !isGenerating else { return }
                        sendPreset(preset)
                    } label: {
                        VStack(spacing: 2) {
                            Text(preset.icon).font(.title3)
                            Text(preset.label).font(.caption2)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(isGenerating)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Chat Log

    private var chatLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        emptyChatHint
                    } else {
                        ForEach(messages) { msg in
                            chatBubble(msg)
                                .id(msg.id)
                        }
                        if isGenerating, messages.last?.role != .assistant {
                            typingIndicator.id("typing")
                        }
                    }
                }
                .padding()
            }
            .onChange(of: messages.last?.id) { _, _ in
                if let lastId = messages.last?.id {
                    withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                }
            }
            .onChange(of: messages.last?.text) { _, _ in
                if let lastId = messages.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    private var emptyChatHint: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("プリセット質問または自由入力で\nAIに質問できます")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            // 空DBのときはヒントを表示
            if (try? db.fetchAll().isEmpty) ?? true {
                Text("💡 避難者を登録すると、実データに基づいたAI応答が可能になります")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func chatBubble(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 40) }
            VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 4) {
                Text(msg.role == .user ? "あなた" : "AIアシスタント")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(msg.text)
                    .font(.body)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        msg.role == .user ? Color.blue.opacity(0.15) : Color.gray.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            if msg.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 4) {
                Circle().frame(width: 6, height: 6)
                Circle().frame(width: 6, height: 6)
                Circle().frame(width: 6, height: 6)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("質問を入力...", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($inputFocused)
                .disabled(isGenerating)

            Button {
                Task { await sendMessage() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Color.blue : Color.gray, in: Circle())
            }
            .disabled(!canSend)
        }
        .padding()
    }

    private var canSend: Bool {
        !isGenerating &&
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    /// プリセット送信: コード生成された確定テキストを即座に表示する。
    /// AI推論を介さず、データベースの集計結果をそのまま集計トークンとして表示するため、
    /// 精度100%・生成も即時。E2Bのセクション跨ぎ不可・似たラベル混同問題を根本的に回避する。
    private func sendPreset(_ preset: (icon: String, label: String, kind: ShelterAnalytics.PresetKind)) {
        // 表示上のユーザーメッセージはラベル(例: 「怪我人の状況」)をそのまま採用
        messages.append(ChatMessage(role: .user, text: preset.label))

        // 確定テキストを生成してassistantメッセージとして追加
        let answer = ShelterAnalytics.generatePresetAnswer(preset.kind, db: db)
        messages.append(ChatMessage(role: .assistant, text: answer))
    }

    private func loadModel() async {
        do {
            try await gemma.loadModel()
        } catch {
            errorMsg = "モデル読み込み失敗: \(error.localizedDescription)"
            showError = true
        }
    }

    private func sendMessage() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        // 二重送信防止：モデル未ロード時は即時エラー表示
        guard gemma.isModelLoaded else {
            errorMsg = "AIモデルがロードされていません。「AIモデルを読み込む」を押してください。"
            showError = true
            return
        }

        // ユーザーメッセージを追加
        messages.append(ChatMessage(role: .user, text: trimmed))
        inputText = ""
        inputFocused = false
        isGenerating = true
        defer { isGenerating = false }

        // コンテキストを毎回再生成（シングルターン）
        let context = ShelterAnalytics.generateContext(db: db)

        // 空のアシスタントメッセージを追加してストリーミング更新
        // 追跡は "最後のassistantメッセージ" ベースで、indexのズレを避ける
        messages.append(ChatMessage(role: .assistant, text: ""))

        do {
            _ = try await gemma.chat(
                contextText: context,
                userMessage: trimmed,
                onToken: { token in
                    Task { @MainActor in
                        // 最後の assistant メッセージを更新
                        if let lastIdx = messages.indices.last,
                           messages[lastIdx].role == .assistant {
                            messages[lastIdx].text += token
                        }
                    }
                }
            )
        } catch {
            if let lastIdx = messages.indices.last,
               messages[lastIdx].role == .assistant {
                messages[lastIdx].text = "⚠️ エラー: \(error.localizedDescription)"
            }
        }
    }
}

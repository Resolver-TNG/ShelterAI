import SwiftUI
import AVFoundation
import UIKit
import Vision
import CoreMedia

/// カメラでカードを撮影 → 解析画面（fullScreenCover）→ onResult
struct CardScanView: View {
    let onResult: (UIImage) -> Void
    let onResultOCR: ((CardOCRService.CardInfo) -> Void)?
    let onSkip: () -> Void

    @EnvironmentObject var gemma: GemmaService

    @StateObject private var camera = CameraViewModel()
    @State private var isProcessing = false
    @State private var errorMsg: String?
    @State private var capturedImage: UIImage?
    @State private var showAnalysis = false
    @State private var didAutoCapture = false

    var body: some View {
        ZStack {
            // カメラプレビュー（黒背景でデバッグ視認性向上）
            Color.black.ignoresSafeArea()

            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            VStack {
                Spacer().frame(height: 60)

                Text(statusMessage)
                    .foregroundStyle(.white)
                    .font(.subheadline).bold()
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: Capsule())
                    .animation(.easeInOut(duration: 0.2), value: camera.detectionState)

                if !camera.isAuthorized {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "camera.metering.unknown")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("カメラへのアクセスが許可されていません")
                            .foregroundStyle(.white)
                            .font(.subheadline).bold()
                        Text("「設定」アプリで安否確認のカメラ利用を許可してください。")
                            .foregroundStyle(.white.opacity(0.8))
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("設定を開く")
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20).padding(.vertical, 10)
                                .background(.blue, in: Capsule())
                        }
                    }
                    .padding(24)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)
                    Spacer()
                } else {
                    Spacer()

                    // ガイドフレーム（検出状態に応じて色が変化）
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(frameColor, lineWidth: frameLineWidth)
                        .frame(width: 320, height: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(frameFillColor)
                        )
                        .scaleEffect(camera.detectionState == .stable ? 1.04 : 1.0)
                        .animation(
                            camera.detectionState == .stable
                                ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                                : .easeInOut(duration: 0.25),
                            value: camera.detectionState
                        )

                    Spacer()
                }

                if isProcessing {
                    ProgressView("撮影中...")
                        .foregroundStyle(.white)
                        .padding()
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                } else if camera.isAuthorized {
                    HStack(spacing: 24) {
                        Button { onSkip() } label: {
                            Text("スキップ（手動入力）")
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(.gray.opacity(0.7), in: Capsule())
                        }

                        Button { capture() } label: {
                            ZStack {
                                Circle()
                                    .stroke(.white.opacity(0.5), lineWidth: 4)
                                    .frame(width: 80, height: 80)
                                Circle()
                                    .fill(.white)
                                    .frame(width: 68, height: 68)
                            }
                        }
                        .disabled(!camera.isSessionRunning)
                    }
                }

                if let errorMsg {
                    Text(errorMsg)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding()
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                }

                Spacer().frame(height: 40)
            }
        }
        .navigationTitle("カード読み取り")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            didAutoCapture = false
            camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: camera.detectionState) { _, newValue in
            // 安定検出 → 自動シャッター（一度だけ）
            if newValue == .stable, !didAutoCapture, !isProcessing, capturedImage == nil {
                didAutoCapture = true
                capture()
            }
        }
        .fullScreenCover(isPresented: $showAnalysis) {
            if let image = capturedImage {
                AnalyzingOverlay(
                    image: image,
                    onComplete: { _ in
                        showAnalysis = false
                        onResult(image)
                    },
                    onCancel: {
                        showAnalysis = false
                    }
                )
                .environmentObject(gemma)
            }
        }
    }

    private func capture() {
        guard camera.isSessionRunning else {
            errorMsg = "カメラの起動を待っています..."
            return
        }
        isProcessing = true
        errorMsg = nil
        // 撮影トリガー後はリアルタイム検出を停止（負荷軽減 + 二重発火防止）
        camera.suspendDetection()
        camera.capturePhoto { image in
            // capturePhoto内のcompletionは既にMainActor上で呼ばれる
            isProcessing = false
            guard let image else {
                errorMsg = "撮影に失敗しました"
                // 失敗時は自動キャプチャをリセット（再試行可能に）
                didAutoCapture = false
                camera.resumeDetection()
                return
            }
            capturedImage = image
            // fullScreenCoverを次のRunLoopで起動（State更新の確実な反映）
            DispatchQueue.main.async {
                showAnalysis = true
            }
        }
    }

    // MARK: - 状態に応じたUI表現

    private var statusMessage: String {
        if isProcessing {
            return "撮影します..."
        }
        switch camera.detectionState {
        case .idle:
            return "カードをガイド枠に合わせてください"
        case .detecting:
            return "カードを検出中...そのまま保持してください"
        case .stable:
            return "撮影します..."
        }
    }

    private var frameColor: Color {
        switch camera.detectionState {
        case .idle: return .white
        case .detecting: return .green.opacity(0.85)
        case .stable: return .green
        }
    }

    private var frameFillColor: Color {
        switch camera.detectionState {
        case .idle: return .white.opacity(0.05)
        case .detecting: return .green.opacity(0.08)
        case .stable: return .green.opacity(0.15)
        }
    }

    private var frameLineWidth: CGFloat {
        camera.detectionState == .idle ? 2 : 3
    }
}

// MARK: - 解析オーバーレイ（fullScreenCover）

struct AnalyzingOverlay: View {
    let image: UIImage
    let onComplete: (CardAnalysisResult) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var gemma: GemmaService
    @State private var errorMessage: String?
    @State private var started = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                // 撮影した画像を表示
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.top, 60)

                Spacer()

                if let errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Button("閉じる") { onCancel() }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24).padding(.vertical, 12)
                            .background(.blue, in: Capsule())
                    }
                } else {
                    // プログレス表示
                    VStack(spacing: 16) {
                        Text("\(gemma.progressPercent)%")
                            .foregroundStyle(.white)
                            .font(.system(size: 56, weight: .bold, design: .monospaced))
                            // animation: 値変化を滑らかに表示
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.25), value: gemma.progressPercent)

                        ProgressView(value: Double(gemma.progressPercent), total: 100)
                            .progressViewStyle(.linear)
                            .tint(.green)
                            .frame(maxWidth: 260)
                            .animation(.easeOut(duration: 0.25), value: gemma.progressPercent)

                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                            Text(gemma.progressStep.isEmpty ? "解析準備中..." : gemma.progressStep)
                                .foregroundStyle(.white)
                                .font(.subheadline)
                                .id(gemma.progressStep) // 文字列変化でアニメ起動
                                .transition(.opacity)
                        }
                    }
                }

                Spacer()

                Button("キャンセル") { onCancel() }
                    .foregroundStyle(.white.opacity(0.6))
                    .font(.caption)
                    .padding(.bottom, 40)
            }
        }
        .task {
            guard !started else { return }
            started = true
            do {
                let r = try await gemma.analyzeCard(image: image)
                onComplete(r)
            } catch {
                errorMessage = "解析に失敗しました: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Camera ViewModel

/// AVCaptureSession を専用serial queueで管理するViewModel
///
/// 設計:
/// - `session` は `nonisolated` (sessionQueue で操作)
/// - `@Published` の状態 (`isAuthorized`, `isSessionRunning`, `detectionState`) は `@MainActor`
/// - `PhotoCaptureDelegate` は強参照で保持（GC防止）
/// - `AVCaptureVideoDataOutput` で `VNDetectRectanglesRequest` を ~5fps で走らせ、
///   リアルタイムにカード検出 → 安定したら自動シャッターをトリガーさせる
final class CameraViewModel: NSObject, ObservableObject {

    /// 検出状態
    enum DetectionState: Equatable {
        case idle        // 未検出
        case detecting   // 検出中（不安定）
        case stable      // 連続検出で安定 → 自動撮影トリガー
    }

    /// AVCaptureSession (sessionQueue で操作するためnonisolated)
    nonisolated let session = AVCaptureSession()

    @MainActor @Published var isAuthorized: Bool = false
    @MainActor @Published var isSessionRunning: Bool = false
    @MainActor @Published var detectionState: DetectionState = .idle

    private let sessionQueue = DispatchQueue(label: "anpi.camera.session", qos: .userInitiated)
    private let detectionQueue = DispatchQueue(label: "anpi.camera.detection", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false

    /// PhotoCaptureDelegate を強参照（GC防止）
    /// AVCapturePhotoOutput.capturePhoto(with:delegate:) は delegate を weak で保持するため
    private var photoDelegates: [PhotoCaptureDelegate] = []

    // MARK: - Realtime detection state（detectionQueue上でのみアクセス）

    /// 検出処理のスロットリング（~5fps）
    private var lastDetectionTime: CFTimeInterval = 0
    private let detectionInterval: CFTimeInterval = 0.2 // 200ms

    /// 連続検出フレーム数と安定判定閾値
    private var consecutiveDetectionCount: Int = 0
    /// 7フレーム連続 ≒ ~1.4秒（0.2s間隔）— 多少余裕を見る
    private let stabilityThreshold: Int = 7

    /// 撮影トリガー後やビュー終了時に検出を一時停止するフラグ（二重発火防止）
    private var detectionSuspended: Bool = false

    // MARK: - Lifecycle

    func start() {
        // 権限チェック → セッション起動
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            Task { @MainActor in self.isAuthorized = true }
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                Task { @MainActor in self.isAuthorized = granted }
                if granted {
                    self.startSession()
                }
            }
        case .denied, .restricted:
            Task { @MainActor in self.isAuthorized = false }
        @unknown default:
            Task { @MainActor in self.isAuthorized = false }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor [weak self] in
                self?.isSessionRunning = false
                self?.detectionState = .idle
            }
        }
        // 検出関連状態もリセット
        detectionQueue.async { [weak self] in
            self?.consecutiveDetectionCount = 0
            self?.lastDetectionTime = 0
        }
    }

    /// 撮影トリガー直後にリアルタイム検出を一時停止する
    func suspendDetection() {
        detectionQueue.async { [weak self] in
            self?.detectionSuspended = true
            self?.consecutiveDetectionCount = 0
        }
    }

    /// 撮影失敗時等に検出を再開する
    func resumeDetection() {
        detectionQueue.async { [weak self] in
            self?.detectionSuspended = false
            self?.consecutiveDetectionCount = 0
        }
        Task { @MainActor [weak self] in
            self?.detectionState = .idle
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.configureSession()
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let running = self.session.isRunning
            Task { @MainActor [weak self] in
                self?.isSessionRunning = running
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        // 背面カメラを優先。なければ前面（iPad前面のみ等のケース対応）
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)

        guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
            print("[CameraViewModel] No camera device available")
            return
        }

        // 既存のinputs/outputsをクリア（再構成対応）
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }

        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            print("[CameraViewModel] Cannot add input")
            return
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        } else {
            print("[CameraViewModel] Cannot add photoOutput")
            return
        }

        // リアルタイムフレーム取得用（カード検出パイプラインへ）
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: detectionQueue)
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            // プレビューと同じ向き（Portrait）に合わせる
            if let connection = videoDataOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                } else if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        } else {
            print("[CameraViewModel] Cannot add videoDataOutput (continuing without realtime detection)")
        }

        isConfigured = true
    }

    // MARK: - Capture

    /// 写真を撮影。completion はMainActor上で呼ばれる
    func capturePhoto(completion: @escaping @MainActor (UIImage?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else {
                Task { @MainActor in completion(nil) }
                return
            }

            let settings = AVCapturePhotoSettings()
            // iPad/iPhone両方でフラッシュ自動
            if self.photoOutput.supportedFlashModes.contains(.auto) {
                settings.flashMode = .auto
            }

            let captureID = UUID()
            let delegate = PhotoCaptureDelegate(id: captureID) { [weak self] image in
                // completion呼び出し
                Task { @MainActor in
                    completion(image)
                }
                // 強参照解放（次の撮影のため）
                self?.sessionQueue.async {
                    self?.photoDelegates.removeAll { $0.id == captureID }
                }
            }
            // GC防止のため強参照保持
            self.photoDelegates.append(delegate)
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

// MARK: - Photo Capture Delegate

/// AVCapturePhotoCaptureDelegate実装
/// AVCapturePhotoOutputがdelegateをweak保持するため、CameraViewModel側で強参照を維持する必要がある
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let id: UUID
    private let completion: (UIImage?) -> Void
    private var didComplete = false

    init(id: UUID = UUID(), completion: @escaping (UIImage?) -> Void) {
        self.id = id
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard !didComplete else { return }
        didComplete = true

        if let error {
            print("[PhotoCaptureDelegate] Error: \(error)")
            completion(nil)
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        completion(image)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        // didFinishProcessingPhoto が呼ばれずにエラー終了するケースのフォールバック
        guard !didComplete else { return }
        if let error {
            didComplete = true
            print("[PhotoCaptureDelegate] Capture error: \(error)")
            completion(nil)
        }
    }
}

// MARK: - Camera Preview

/// AVCaptureVideoPreviewLayerをホストするUIView
/// `layer`を直接`AVCaptureVideoPreviewLayer`にすることで`bounds`変化に追従する
final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }

    var session: AVCaptureSession? {
        get { previewLayer.session }
        set { previewLayer.session = newValue }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        view.session = session

        // iPad/iPhone回転対応（Portrait固定アプリだが念のため）
        if #available(iOS 17.0, *) {
            view.previewLayer.connection?.videoRotationAngle = 90
        } else {
            view.previewLayer.connection?.videoOrientation = .portrait
        }
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if uiView.session !== session {
            uiView.session = session
        }
    }
}

// MARK: - Realtime Card Detection (AVCaptureVideoDataOutputSampleBufferDelegate)

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {

    /// 各フレームを受け取り、~5fpsでVNDetectRectanglesRequestを実行する
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // 検出が一時停止中（撮影中・撮影直後）はスキップ
        if detectionSuspended { return }

        // 5fps制限（200ms間隔）— バッテリー/発熱を抑制
        let now = CACurrentMediaTime()
        guard now - lastDetectionTime >= detectionInterval else { return }
        lastDetectionTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // CardPreprocessor.swift と同じパラメータ
        let request = VNDetectRectanglesRequest { [weak self] request, _ in
            guard let self else { return }
            let detected = (request.results as? [VNRectangleObservation])?.first != nil
            self.handleDetectionResult(detected: detected)
        }
        request.minimumAspectRatio = 0.4
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.2
        request.minimumConfidence = 0.6
        request.maximumObservations = 1

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // 検出失敗は無視（次フレームで再試行）
            #if DEBUG
            print("[CameraViewModel] Vision request failed: \(error)")
            #endif
        }
    }

    /// 検出結果を受けて連続カウントを更新し、UIに反映する
    /// （detectionQueue上で呼ばれる）
    private func handleDetectionResult(detected: Bool) {
        if detectionSuspended { return }

        if detected {
            consecutiveDetectionCount += 1
        } else {
            consecutiveDetectionCount = 0
        }

        let count = consecutiveDetectionCount
        let threshold = stabilityThreshold
        Task { @MainActor [weak self] in
            guard let self else { return }
            // すでに stable をトリガー済みの場合は維持（CardScanView側でsuspendDetectionされる）
            if self.detectionState == .stable { return }
            if count >= threshold {
                self.detectionState = .stable
            } else if count > 0 {
                self.detectionState = .detecting
            } else {
                self.detectionState = .idle
            }
        }
    }
}

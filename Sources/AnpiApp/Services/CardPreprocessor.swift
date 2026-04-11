import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// カード画像の前処理サービス
///
/// 撮影された生画像を SigLIP / Gemma マルチモーダル入力に最適化する:
/// 1. VNDetectRectanglesRequest でカード矩形領域を検出
/// 2. CIPerspectiveCorrection で台形補正（傾き・歪み補正）
/// 3. CIColorControls でコントラスト・明るさ正規化
/// 4. 最大 1024px にリサイズ（短辺基準で SigLIP 入力に最適化）
///
/// バックグラウンドスレッドで動作（@MainActor 不要）
struct CardPreprocessor {

    // MARK: - Public API

    /// 入力画像を解析・補正・リサイズして返す
    /// - Parameters:
    ///   - image: カメラまたはフォトピッカーから取得した生 UIImage
    ///   - maxDimension: 出力画像の最大辺ピクセル数（デフォルト 1024）
    /// - Returns: 前処理済み UIImage（失敗時は単純リサイズのみのフォールバック）
    static func process(_ image: UIImage, maxDimension: CGFloat = 1024) async -> UIImage {
        // CGImage が無いケースは早期に元画像を返す
        guard let cgImage = image.cgImage else {
            return image
        }

        // 入力 CIImage（向きを補正してから処理）
        let orientedCIImage = CIImage(cgImage: cgImage)
            .oriented(forExifOrientation: exifOrientation(from: image.imageOrientation))

        // 1. 矩形検出 → 透視補正
        let corrected: CIImage
        if let perspective = try? await detectAndCorrect(ciImage: orientedCIImage) {
            corrected = perspective
        } else {
            corrected = orientedCIImage
        }

        // 2. コントラスト/明るさ正規化
        let normalized = normalize(corrected)

        // 3. リサイズ（最大辺 maxDimension）
        let resized = resize(normalized, maxDimension: maxDimension)

        // 4. UIImage に戻す
        return renderUIImage(from: resized) ?? image
    }

    // MARK: - 1. Rectangle Detection + Perspective Correction

    /// VNDetectRectanglesRequest でカード領域を検出し、CIPerspectiveCorrection で透視補正
    private static func detectAndCorrect(ciImage: CIImage) async throws -> CIImage? {
        let observation: VNRectangleObservation? = try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = request.results as? [VNRectangleObservation] ?? []
                // 最大面積の矩形を採用
                let best = results.max { lhs, rhs in
                    lhs.boundingBox.width * lhs.boundingBox.height
                        < rhs.boundingBox.width * rhs.boundingBox.height
                }
                continuation.resume(returning: best)
            }
            // 身分証想定: アスペクト比は緩めに、信頼度は中庸
            request.minimumAspectRatio = 0.4   // 縦横比の許容範囲
            request.maximumAspectRatio = 1.0
            request.minimumSize = 0.2          // 画像内の最小占有率
            request.minimumConfidence = 0.6
            request.maximumObservations = 1

            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }

        guard let rect = observation else {
            return nil
        }

        // VN は normalized 座標 [0,1] (左下原点)。CIImage extent に変換。
        let extent = ciImage.extent
        let topLeft = CGPoint(
            x: rect.topLeft.x * extent.width,
            y: rect.topLeft.y * extent.height
        )
        let topRight = CGPoint(
            x: rect.topRight.x * extent.width,
            y: rect.topRight.y * extent.height
        )
        let bottomLeft = CGPoint(
            x: rect.bottomLeft.x * extent.width,
            y: rect.bottomLeft.y * extent.height
        )
        let bottomRight = CGPoint(
            x: rect.bottomRight.x * extent.width,
            y: rect.bottomRight.y * extent.height
        )

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ciImage
        filter.topLeft = topLeft
        filter.topRight = topRight
        filter.bottomLeft = bottomLeft
        filter.bottomRight = bottomRight

        return filter.outputImage
    }

    // MARK: - 2. Brightness / Contrast Normalization

    /// CIColorControls でコントラスト・明るさを軽く強調
    private static func normalize(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.contrast = 1.10      // +10% コントラスト
        filter.brightness = 0.02    // 軽く持ち上げ
        filter.saturation = 1.0     // 彩度は維持（カード色情報を保持）
        return filter.outputImage ?? image
    }

    // MARK: - 3. Resize

    /// 最大辺 maxDimension に収まるよう CILanczosScaleTransform でリサイズ
    private static func resize(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let extent = image.extent
        let longest = max(extent.width, extent.height)
        guard longest > maxDimension, longest > 0 else { return image }

        let scale = maxDimension / longest
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1.0
        return filter.outputImage ?? image
    }

    // MARK: - 4. Render

    /// CIImage を UIImage に変換
    private static func renderUIImage(from ciImage: CIImage) -> UIImage? {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        // 原点が負になるケースに備えて extent を整える
        let rect = ciImage.extent.isInfinite ? CGRect(x: 0, y: 0, width: 1024, height: 1024) : ciImage.extent
        guard let cgImage = context.createCGImage(ciImage, from: rect) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Helpers

    /// UIImage.Orientation -> EXIF Orientation 値変換
    private static func exifOrientation(from orientation: UIImage.Orientation) -> Int32 {
        switch orientation {
        case .up:            return 1
        case .down:          return 3
        case .left:          return 8
        case .right:         return 6
        case .upMirrored:    return 2
        case .downMirrored:  return 4
        case .leftMirrored:  return 5
        case .rightMirrored: return 7
        @unknown default:    return 1
        }
    }
}

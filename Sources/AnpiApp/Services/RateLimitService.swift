import Foundation
import Combine

/// 1分あたり最大5件・超過時60秒クールダウン
final class RateLimitService: ObservableObject {
    private let maxPerMinute = 5
    private let cooldownSeconds: TimeInterval = 60

    @Published var isBlocked: Bool = false
    @Published var remainingCooldown: Int = 0

    private var registeredTimestamps: [Date] = []
    private var cooldownTimer: Timer?

    /// 登録を試みる。trueなら許可、falseならブロック
    func requestRegistration() -> Bool {
        let now = Date()
        // 1分以内のスタンプだけ残す
        registeredTimestamps = registeredTimestamps.filter {
            now.timeIntervalSince($0) < 60
        }

        if isBlocked { return false }

        if registeredTimestamps.count >= maxPerMinute {
            startCooldown()
            return false
        }

        registeredTimestamps.append(now)
        return true
    }

    private func startCooldown() {
        isBlocked = true
        remainingCooldown = Int(cooldownSeconds)
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            remainingCooldown -= 1
            if remainingCooldown <= 0 {
                isBlocked = false
                cooldownTimer?.invalidate()
                registeredTimestamps.removeAll()
            }
        }
    }
}

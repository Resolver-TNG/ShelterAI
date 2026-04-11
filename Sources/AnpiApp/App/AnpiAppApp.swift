import SwiftUI

@main
struct AnpiAppApp: App {
    @StateObject private var db: DatabaseService
    @StateObject private var location = LocationService()
    @StateObject private var audio = AudioService()
    @StateObject private var rateLimit = RateLimitService()
    @StateObject private var gemma = GemmaService()
    @StateObject private var modelManager = ModelManager()

    @AppStorage("modelSetupDone") private var modelSetupDone = false

    init() {
        do {
            let service = try DatabaseService()
            _db = StateObject(wrappedValue: service)
        } catch {
            fatalError("DatabaseService initialization failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !modelSetupDone {
                    ModelSetupView(
                        onComplete: { modelSetupDone = true },
                        onSkip: { modelSetupDone = true }
                    )
                } else {
                    LaunchModeView()
                }
            }
            .environmentObject(db)
            .environmentObject(location)
            .environmentObject(audio)
            .environmentObject(rateLimit)
            .environmentObject(gemma)
            .environmentObject(modelManager)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willTerminateNotification
                )
            ) { _ in
                // テストモードデータの自動削除
                try? db.deleteTestData()
            }
        }
    }
}

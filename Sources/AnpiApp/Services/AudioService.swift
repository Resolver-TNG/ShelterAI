import AVFoundation

final class AudioService: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, lang: String = "ja-JP") {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: lang)
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func announceComplete(name: String) { speak("\(name)さんの情報を記録しました") }
    func announceRateLimit() { speak("しばらくお待ちください") }
}

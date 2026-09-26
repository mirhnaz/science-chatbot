import AVFoundation
import NaturalLanguage
import Observation

/// Read aloud using the iPad's built-in voices; works offline.
///
/// Apps cannot use Siri's own voices, but iOS offers downloadable Enhanced
/// and Premium voices (Settings → Accessibility → Read & Speak → Voices) that
/// sound far more natural than the default compact ones. We pick the best
/// installed voice for the answer's language unless one was chosen in Settings.
@MainActor @Observable
final class Speech: NSObject, AVSpeechSynthesizerDelegate {
    /// UserDefaults key for the voice chosen in Settings ("" = automatic).
    static let voiceKey = "voice"

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ text: String) {
        if isSpeaking { stop(); return }
        speak(text, voice: Self.voice(for: text))
    }

    /// Speaks a short sample, for the Settings preview button.
    func preview(_ voice: AVSpeechSynthesisVoice?) {
        stop()
        speak("Hi! Let's find out how rainbows form.", voice: voice ?? Self.voice(for: "Hello"))
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func speak(_ text: String, voice: AVSpeechSynthesisVoice?) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    // MARK: Choosing a voice

    /// Installed voices for a language, best quality first. Novelty voices
    /// (Bells, Bubbles, …) and Personal Voice are left out.
    static func voices(language: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { a, b in
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                // Prefer the device's own region, for example en-IN over en-US.
                let region = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
                if (a.language == region) != (b.language == region) { return a.language == region }
                return a.name < b.name
            }
    }

    /// The device language, for example "en".
    static var deviceLanguage: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    /// The chosen voice if it matches the answer's language; otherwise the
    /// best installed voice for that language.
    static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? deviceLanguage
        let chosen = UserDefaults.standard.string(forKey: voiceKey)
            .flatMap(AVSpeechSynthesisVoice.init(identifier:))
        if let chosen, chosen.language.hasPrefix(language) { return chosen }
        return voices(language: language).first ?? AVSpeechSynthesisVoice(language: language)
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in isSpeaking = false }
    }
}

extension AVSpeechSynthesisVoiceQuality {
    var label: String {
        switch self {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Standard"
        }
    }
}

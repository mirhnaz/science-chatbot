import AVFoundation
import NaturalLanguage
import Observation

/// Read aloud, offline.
///
/// English answers use the natural Kokoro voice (see NaturalVoice.swift) when
/// it is downloaded and switched on. Each sentence is generated while the
/// previous one plays, so there are no gaps. Everything else, or any failure,
/// uses Apple's built-in voices: Siri's own voice is not available to apps,
/// but downloadable Enhanced and Premium voices are.
@MainActor @Observable
final class Speech: NSObject, AVSpeechSynthesizerDelegate {
    /// UserDefaults key for the Apple voice chosen in Settings ("" = automatic).
    static let voiceKey = "voice"
    /// UserDefaults key: use the natural voice when it is installed.
    static let naturalKey = "naturalVoice"

    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var natural: Task<Void, Never>?
    /// Changes on every start and stop, so playback callbacks from an
    /// earlier reading are ignored.
    private var session = 0
    private var queued = 0
    private var allQueued = false
    private(set) var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
        engine.attach(player)
    }

    func toggle(_ text: String) {
        if isSpeaking { stop(); return }
        let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? Self.deviceLanguage
        if language == "en", Self.naturalEnabled, NaturalVoice.isInstalled {
            speakNaturally(text)
        } else {
            speak(text, voice: Self.voice(for: text))
        }
    }

    /// Speaks a short sample, for the Settings preview buttons.
    func preview(natural: Bool, voice: AVSpeechSynthesisVoice?) {
        stop()
        let sample = "Hi! Let's find out how rainbows form."
        if natural, NaturalVoice.isInstalled {
            speakNaturally(sample)
        } else {
            speak(sample, voice: voice ?? Self.voice(for: sample))
        }
    }

    func stop() {
        session += 1
        natural?.cancel()
        natural = nil
        player.stop()
        engine.stop()
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: Natural voice

    private func speakNaturally(_ text: String) {
        session += 1
        let current = session
        queued = 0
        allQueued = false
        isSpeaking = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        natural = Task {
            var format: AVAudioFormat?
            do {
                for sentence in Self.sentences(in: text) {
                    let (samples, rate) = try await NaturalVoiceEngine.shared.generate(sentence)
                    guard current == session else { return }
                    if format == nil {
                        format = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 1)
                        engine.connect(player, to: engine.mainMixerNode, format: format)
                        try engine.start()
                        player.play()
                    }
                    guard let format, let buffer = Self.buffer(samples, format: format) else { continue }
                    queued += 1
                    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                        Task { @MainActor in self.played(in: current) }
                    }
                }
                allQueued = true
                if queued == 0 { finish(current) }
            } catch {
                // Could not load or run the model: read with Apple's voice.
                guard current == session, format == nil else { return }
                speak(text, voice: Self.voice(for: text))
            }
        }
    }

    private func played(in current: Int) {
        guard current == session else { return }
        queued -= 1
        if allQueued, queued == 0 { finish(current) }
    }

    private func finish(_ current: Int) {
        guard current == session else { return }
        engine.stop()
        isSpeaking = false
    }

    private static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }

    /// Splits an answer into sentences, so the first one can start playing
    /// while the rest are generated.
    static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { text[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static var naturalEnabled: Bool {
        UserDefaults.standard.object(forKey: naturalKey) as? Bool ?? true
    }

    // MARK: Apple voices

    private func speak(_ text: String, voice: AVSpeechSynthesisVoice?) {
        session += 1
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        isSpeaking = true
        synthesizer.speak(utterance)
    }

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

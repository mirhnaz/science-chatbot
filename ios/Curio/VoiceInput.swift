import AVFoundation
import Observation
import Speech

/// "Speak your question": turns speech into text in the question box, live,
/// as the child talks. Uses iOS 26's SpeechAnalyzer with a DictationTranscriber
/// (keyboard-style dictation with punctuation), which runs **on this device
/// only**, so no audio leaves the iPad. Apple's speech model for the language
/// is downloaded once if the device lacks it. The older SFSpeechRecognizer
/// dropped earlier words after a pause (showing only the last ones); this
/// engine keeps finished phrases and replaces only the phrase in progress.
///
/// Listening waits a while for the first words, then stops by itself after a
/// pause, or when the child taps the button again. If it stops without
/// hearing anything, it says so (with the system's reason, for a grown-up).
/// The text is never sent automatically: the child checks it and taps Ask.
@MainActor @Observable
final class VoiceInput {
    private(set) var isListening = false
    /// Shown when permission is missing or listening failed.
    var problem: String?
    /// Whether this device can dictate offline in the current language
    /// (checked once at launch; the microphone button is hidden until then).
    private(set) var isAvailable = false

    private var locale: Locale?
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var pauseTimer: Task<Void, Never>?
    private var limitTimer: Task<Void, Never>?
    /// Phrases the transcriber has finished, and whether any words arrived.
    private var finished = AttributedString()
    private var heardWords = false

    /// Waits this long for the first words (children often pause first)…
    private static let firstWords: Duration = .seconds(8)
    /// …then stops after this long without new words.
    private static let pause: Duration = .seconds(3)
    /// And after this long in total.
    private static let limit: Duration = .seconds(60)

    init() {
        Task {
            locale = await DictationTranscriber.supportedLocale(equivalentTo: .current)
            isAvailable = locale != nil
        }
    }

    /// Starts listening; `heard` receives all the words so far each time they change.
    func start(heard: @escaping (String) -> Void) async {
        guard !isListening, let locale else { return }
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard speechAllowed, micAllowed else {
            problem = "To ask out loud, a grown-up can allow Microphone and Speech Recognition for Curio in Settings."
            return
        }
        isListening = true
        finished = AttributedString()
        heardWords = false
        do {
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
            // Apple's on-device model for this language, once per device.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard isListening else { return }  // tapped again while downloading
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw VoiceError.noFormat
            }
            let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
            self.input = input

            // Live results: finished phrases stay; the one in progress is
            // replaced each time until it is finished too.
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self, self.isListening else { return }
                        let text: AttributedString
                        if result.isFinal {
                            self.finished += result.text
                            text = self.finished
                        } else {
                            text = self.finished + result.text
                        }
                        let words = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !words.isEmpty {
                            heard(words)
                            self.heardWords = true
                            self.restartPauseTimer()
                        }
                    }
                } catch {
                    guard let self, self.isListening else { return }
                    if !self.heardWords { self.problem = Self.nothingHeard(error.localizedDescription) }
                    self.stop()
                }
            }

            let session = AVAudioSession.sharedInstance()
            // Voice processing (as in FaceTime): the iPad's microphones
            // focus on the voice, with automatic gain and noise and echo
            // reduction. Without it the iPad's mics gave the model audio so
            // quiet that it caught only the first loud words.
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            if !engine.inputNode.isVoiceProcessingEnabled {
                try engine.inputNode.setVoiceProcessingEnabled(true)
            }
            // The microphone's format, converted to the one the model wants.
            let micFormat = engine.inputNode.outputFormat(forBus: 0)
            guard let converter = AVAudioConverter(from: micFormat, to: format) else { throw VoiceError.noFormat }
            // With voice processing the first channel is the processed voice
            // (some devices report extra, unprocessed channels): take only it.
            converter.channelMap = [0]
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
                if let converted = Self.convert(buffer, with: converter, to: format) {
                    input.yield(AnalyzerInput(buffer: converted))
                }
            }
            engine.prepare()
            try engine.start()
            try await analyzer.start(inputSequence: stream)

            restartPauseTimer()
            limitTimer = Task { [weak self] in
                try? await Task.sleep(for: Self.limit)
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            problem = "The microphone isn’t available right now. Please type your question instead.\n\n(For a grown-up: \(error.localizedDescription))"
            stop()
        }
    }

    func stop() {
        guard isListening || engine.isRunning else { return }
        isListening = false
        pauseTimer?.cancel()
        limitTimer?.cancel()
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        input?.finish()
        input = nil
        let analyzer = self.analyzer
        let results = resultsTask
        self.analyzer = nil
        resultsTask = nil
        Task {
            // Let the last phrase finish, then release the model.
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            results?.cancel()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func restartPauseTimer() {
        pauseTimer?.cancel()
        let wait = heardWords ? Self.pause : Self.firstWords
        pauseTimer = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self else { return }
            if !self.heardWords { self.problem = Self.nothingHeard(nil) }
            self.stop()
        }
    }

    /// The message when listening ended before any words arrived.
    private static func nothingHeard(_ reason: String?) -> String {
        let message = "Curio didn’t hear any words. Tap the microphone and start talking."
        return reason.map { "\(message)\n\n(For a grown-up: \($0))" } ?? message
    }

    /// One microphone buffer in the model's format (runs on the audio thread).
    private nonisolated static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                                            to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    private enum VoiceError: LocalizedError {
        case noFormat
        var errorDescription: String? { "No audio format for speech recognition." }
    }
}

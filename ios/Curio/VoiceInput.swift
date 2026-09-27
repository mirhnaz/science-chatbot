import AVFoundation
import Observation
import Speech

/// "Speak your question": turns speech into text in the question box.
/// Recognition runs **on this device only** (`requiresOnDeviceRecognition`),
/// so no audio leaves the iPad; where the device cannot do that for the
/// current language, the microphone button is hidden. Listening stops by
/// itself after a short pause, or when the child taps the button again. The
/// text is never sent automatically: the child checks it and taps Ask.
@MainActor @Observable
final class VoiceInput {
    private(set) var isListening = false
    /// Shown when permission is missing or listening failed.
    var problem: String?

    private let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var pauseTimer: Task<Void, Never>?
    private var limitTimer: Task<Void, Never>?

    /// Stops after this long without new words.
    private static let pause: Duration = .seconds(2.5)
    /// And after this long in total.
    private static let limit: Duration = .seconds(30)

    /// Whether this device can recognise speech offline for the language.
    var isAvailable: Bool { recognizer?.supportsOnDeviceRecognition == true }

    /// Starts listening; `heard` receives the words so far each time they change.
    func start(heard: @escaping (String) -> Void) async {
        guard !isListening, let recognizer, recognizer.supportsOnDeviceRecognition else { return }
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard speechAllowed, micAllowed else {
            problem = "To ask out loud, a grown-up can allow Microphone and Speech Recognition for Curio in the iPad’s Settings."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            self.request = request
            isListening = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let done = error != nil || result?.isFinal == true
                Task { @MainActor in
                    guard let self, self.isListening else { return }
                    if let text, !text.isEmpty {
                        heard(text)
                        self.restartPauseTimer()
                    }
                    if done { self.stop() }
                }
            }
            restartPauseTimer()
            limitTimer = Task { [weak self] in
                try? await Task.sleep(for: Self.limit)
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            problem = "The microphone isn’t available right now. Please type your question instead."
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
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func restartPauseTimer() {
        pauseTimer?.cancel()
        pauseTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }
}

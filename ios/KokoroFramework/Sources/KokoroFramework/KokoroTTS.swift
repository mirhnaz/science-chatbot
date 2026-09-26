import Foundation
import SherpaOnnxC

/// One loaded Kokoro model. Not thread-safe: use it from one task at a time
/// (the app keeps it inside an actor).
public final class KokoroTTS {
    private let tts: OpaquePointer
    public let sampleRate: Int

    /// Loads the model from a folder laid out like sherpa-onnx's
    /// kokoro-multi-lang-v1_0 release: model.onnx, voices.bin, tokens.txt,
    /// lexicon-us-en.txt, and espeak-ng-data/.
    public init?(folder: URL, threads: Int = 4) {
        // The C API reads these strings only while creating the model, so
        // temporary copies freed right after are enough.
        var owned: [UnsafeMutablePointer<CChar>] = []
        defer { owned.forEach { free($0) } }
        func c(_ name: String) -> UnsafePointer<CChar> {
            let pointer = strdup(folder.appendingPathComponent(name).path)!
            owned.append(pointer)
            return UnsafePointer(pointer)
        }

        // Imported C structs start zeroed, like memset(&config, 0, ...).
        var config = SherpaOnnxOfflineTtsConfig()
        config.model.kokoro.model = c("model.onnx")
        config.model.kokoro.voices = c("voices.bin")
        config.model.kokoro.tokens = c("tokens.txt")
        config.model.kokoro.data_dir = c("espeak-ng-data")
        config.model.kokoro.lexicon = c("lexicon-us-en.txt")
        config.model.kokoro.length_scale = 1.0
        config.model.num_threads = Int32(threads)
        config.max_num_sentences = 1
        config.silence_scale = 0.2

        guard let created = SherpaOnnxCreateOfflineTts(&config) else { return nil }
        tts = created
        sampleRate = Int(SherpaOnnxOfflineTtsSampleRate(created))
    }

    deinit {
        SherpaOnnxDestroyOfflineTts(tts)
    }

    /// Speaks `text` with voice `speaker` and returns mono samples in [-1, 1].
    public func generate(_ text: String, speaker: Int, speed: Float = 1.0) -> [Float] {
        var generation = SherpaOnnxGenerationConfig()
        generation.sid = Int32(speaker)
        generation.speed = speed
        generation.silence_scale = 0.2

        guard let audio = SherpaOnnxOfflineTtsGenerateWithConfig(
            tts, text, &generation, nil, nil)
        else { return [] }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        guard let samples = audio.pointee.samples, audio.pointee.n > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: samples, count: Int(audio.pointee.n)))
    }
}

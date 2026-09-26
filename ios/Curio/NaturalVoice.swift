import CryptoKit
import Foundation
import KokoroFramework
import Observation

/// The natural Read aloud voice: Kokoro's "Michael" (am_michael), generated on
/// the iPad, offline. English only; other languages use Apple's voices.
enum NaturalVoice {
    static let name = "Michael"
    /// Speaker number of am_michael in kokoro-multi-lang-v1_0.
    static let speaker = 16
    static let downloadSize = "about 375 MB"

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kokoro", isDirectory: true)
    }

    /// True when the files the model needs are all present.
    static var isInstalled: Bool {
        ["model.onnx", "voices.bin", "tokens.txt", "lexicon-us-en.txt", "espeak-ng-data/phontab"]
            .allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }
}

/// Keeps the Kokoro model loaded and generates one sentence at a time. An
/// actor, like LocalEngine, because the model must not be used by two tasks
/// at once.
actor NaturalVoiceEngine {
    static let shared = NaturalVoiceEngine()
    private var tts: KokoroTTS?

    /// Returns mono samples and their sample rate (24,000 per second).
    func generate(_ sentence: String) throws -> (samples: [Float], sampleRate: Int) {
        if tts == nil {
            tts = KokoroTTS(folder: NaturalVoice.folder)
        }
        guard let tts else { throw TutorError.message("The natural voice could not be loaded.") }
        return (tts.generate(sentence, speaker: NaturalVoice.speaker), tts.sampleRate)
    }

    /// Frees the model's memory, for example after the files are deleted.
    func unload() {
        tts = nil
    }
}

/// Downloads the English Kokoro files from a pinned Hugging Face revision.
/// The Chinese files in the same repository are skipped.
@MainActor @Observable
final class NaturalVoiceStore {
    /// csukuangfj/kokoro-multi-lang-v1_0 at a fixed commit, so the files
    /// cannot change under us.
    private static let repository = "csukuangfj/kokoro-multi-lang-v1_0"
    private static let revision = "f7b96bb6bef5c5da4d3aa4f4e0498fbbf62dc78b"
    private static let topFiles: Set = ["model.onnx", "voices.bin", "tokens.txt", "lexicon-us-en.txt", "LICENSE"]

    private(set) var isInstalled = NaturalVoice.isInstalled
    private(set) var progress: Double?
    private(set) var message: String?
    private var task: Task<Void, Never>?

    func download() {
        guard task == nil else { return }
        progress = 0
        message = nil
        task = Task {
            defer { task = nil; progress = nil }
            do {
                try await install()
                isInstalled = true
                message = "Natural voice ready."
            } catch is CancellationError {
                message = "Download cancelled."
            } catch let error as URLError where error.code == .cancelled {
                message = "Download cancelled."
            } catch {
                message = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    func delete() {
        try? FileManager.default.removeItem(at: NaturalVoice.folder)
        isInstalled = false
        message = nil
        Task { await NaturalVoiceEngine.shared.unload() }
    }

    private struct Entry: Decodable {
        struct LFS: Decodable { let oid: String }
        let type: String
        let path: String
        let size: Int
        let lfs: LFS?
    }

    /// Downloads into a temporary folder and renames it when every file has
    /// arrived and the large files match their published SHA-256.
    private func install() async throws {
        let listURL = URL(string:
            "https://huggingface.co/api/models/\(Self.repository)/tree/\(Self.revision)?recursive=1")!
        let (listData, _) = try await URLSession.shared.data(from: listURL)
        let files = try JSONDecoder().decode([Entry].self, from: listData).filter {
            $0.type == "file" && (Self.topFiles.contains($0.path) || $0.path.hasPrefix("espeak-ng-data/"))
        }
        guard files.contains(where: { $0.path == "model.onnx" }) else {
            throw TutorError.message("The voice files were not found online.")
        }

        let partial = NaturalVoice.folder.deletingLastPathComponent()
            .appendingPathComponent("Kokoro.partial", isDirectory: true)
        try? FileManager.default.removeItem(at: partial)
        let total = Double(files.reduce(0) { $0 + $1.size })
        var done = 0.0

        // Large files one at a time with smooth progress; the ~355 small
        // espeak-ng files a few at a time so they do not take minutes.
        let large = files.filter { $0.size > 1_000_000 }
        let small = files.filter { $0.size <= 1_000_000 }
        for file in large {
            let base = done
            try await fetch(file, into: partial) { fraction in
                self.progress = (base + fraction * Double(file.size)) / total
            }
            done += Double(file.size)
            progress = done / total
        }
        for batch in stride(from: 0, to: small.count, by: 8).map({ Array(small[$0..<min($0 + 8, small.count)]) }) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for file in batch {
                    group.addTask { try await self.fetch(file, into: partial, progress: nil) }
                }
                try await group.waitForAll()
            }
            done += Double(batch.reduce(0) { $0 + $1.size })
            progress = done / total
        }

        try? FileManager.default.removeItem(at: NaturalVoice.folder)
        try FileManager.default.moveItem(at: partial, to: NaturalVoice.folder)
        await NaturalVoiceEngine.shared.unload()
    }

    private func fetch(_ file: Entry, into folder: URL, progress: ((Double) -> Void)?) async throws {
        let url = URL(string:
            "https://huggingface.co/\(Self.repository)/resolve/\(Self.revision)/\(file.path)")!
        let reporter = progress.map { report in
            FileProgress { value in Task { @MainActor in report(value) } }
        }
        let (temporary, response) = try await URLSession.shared.download(from: url, delegate: reporter)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw TutorError.message("Could not download \(file.path).")
        }
        // Hash off the main thread: reading 326 MB takes about a second.
        if let expected = file.lfs?.oid,
           try await Task.detached(operation: { try Self.sha256(of: temporary) }).value != expected {
            throw TutorError.message("\(file.path) did not match its checksum.")
        }
        let target = folder.appendingPathComponent(file.path)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
    }

    /// Reads the file in 4 MB pieces so a 326 MB model is not held in memory.
    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Reports one file's download fraction.
private final class FileProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let update: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(update: @escaping @Sendable (Double) -> Void) {
        self.update = update
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [update] progress, _ in
            update(progress.fractionCompleted)
        }
    }
}

import Foundation
import Observation

/// Finds, imports, and downloads the on-device model file (.gguf).
/// Models live in the app's Documents folder, which Finder and the Files app
/// can see, so a model can be copied over a cable with no internet.
@MainActor @Observable
final class ModelStore {
    static let recommendedName = "Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
    static let recommendedURL = URL(string:
        "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/\(recommendedName)")!

    private(set) var models: [URL] = []
    var selectedName: String {
        didSet { UserDefaults.standard.set(selectedName, forKey: "modelName") }
    }
    private(set) var downloadProgress: Double?
    private(set) var message: String?

    private var downloadTask: Task<Void, Never>?

    init() {
        selectedName = UserDefaults.standard.string(forKey: "modelName") ?? ""
        refresh()
    }

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var selectedPath: String? {
        models.first { $0.lastPathComponent == selectedName }?.path ?? models.first?.path
    }

    func refresh() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        models = files.filter { $0.pathExtension.lowercased() == "gguf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if !models.contains(where: { $0.lastPathComponent == selectedName }) {
            selectedName = models.first?.lastPathComponent ?? ""
        }
    }

    /// Copies a model picked in the Files app into Documents.
    func importModel(from source: URL) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let target = Self.folder.appendingPathComponent(source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: source, to: target)
            selectedName = target.lastPathComponent
            message = "Imported \(target.lastPathComponent)."
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
        refresh()
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refresh()
    }

    /// One-time download of the recommended model (about 2.5 GB).
    func downloadRecommended() {
        guard downloadTask == nil else { return }
        downloadProgress = 0
        message = nil
        downloadTask = Task {
            defer { downloadTask = nil; downloadProgress = nil }
            let progress = DownloadProgress { value in
                Task { @MainActor in self.downloadProgress = value }
            }
            do {
                // download(from:) streams straight to a temporary file.
                let (temporary, response) = try await URLSession.shared.download(
                    from: Self.recommendedURL, delegate: progress)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    message = "Download failed. Please try again later."
                    return
                }
                let target = Self.folder.appendingPathComponent(Self.recommendedName)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: temporary, to: target)
                selectedName = Self.recommendedName
                message = "Model downloaded. The iPad can now answer offline."
            } catch is CancellationError {
                message = "Download cancelled."
            } catch let error as URLError where error.code == .cancelled {
                message = "Download cancelled."
            } catch {
                message = "Download failed: \(error.localizedDescription)"
            }
            refresh()
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }
}

/// Reports a download's fraction complete while URLSession writes the file.
private final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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

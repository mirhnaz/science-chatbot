#if DEBUG
import UIKit

/// Debug builds only: helpers for checking layouts without touching the
/// screen, mainly when the iPad app runs on a Mac ("Designed for iPad").
///
/// - `-windowSize 1180x820` fixes the window size (on a Mac, where windows
///   can be resized), for example to check the wide iPad layout.
/// - `-snapshot 30` saves the window as `snapshot.png` in the app's Documents
///   folder after 30 seconds (on a Mac: ~/Library/Containers/…/Data/Documents).
///   The app draws its own window, so no screen-recording permission is needed.
enum DebugCapture {
    @MainActor
    static func start() {
        let arguments = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        if let size = value(after: "-windowSize")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            let target = CGSize(width: size[0], height: size[1])
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.sizeRestrictions?.minimumSize = target
                scene.sizeRestrictions?.maximumSize = target
            }
        }
        if let seconds = value(after: "-snapshot").flatMap(Double.init) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                save()
            }
        }
    }

    @MainActor
    private static func save() {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        guard let window,
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try? image.pngData()?.write(to: folder.appendingPathComponent("snapshot.png"))
    }
}
#endif

import Network
import Observation

/// Tracks whether the iPad has any network path (Wi-Fi or cellular).
/// In airplane mode this is false, so Automatic goes straight to the iPad.
@MainActor @Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        // NWPathMonitor reports on a background queue; hop to the main actor
        // because SwiftUI reads `isOnline`.
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: .global(qos: .utility))
    }
}

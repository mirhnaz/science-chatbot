import SwiftUI

@main
struct CurioApp: App {
    @State private var models = ModelStore()
    @State private var naturalVoice = NaturalVoiceStore()
    @AppStorage("theme") private var theme = "system"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(models)
                .environment(naturalVoice)
                .onAppear(perform: applyTheme)
                .onChange(of: theme, applyTheme)
        }
    }

    /// Sets Light, Dark, or System on every window, sheets included.
    /// `.preferredColorScheme(nil)` often fails to switch back to System after
    /// Light or Dark was chosen, so the window setting is used instead.
    private func applyTheme() {
        let style: UIUserInterfaceStyle = switch theme {
        case "light": .light
        case "dark": .dark
        default: .unspecified
        }
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
    }
}

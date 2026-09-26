import SwiftUI

@main
struct ScienceChatbotApp: App {
    @State private var models = ModelStore()
    @State private var naturalVoice = NaturalVoiceStore()
    @AppStorage("theme") private var theme = "system"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(models)
                .environment(naturalVoice)
                .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
        }
    }
}

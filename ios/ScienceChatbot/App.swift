import SwiftUI

@main
struct ScienceChatbotApp: App {
    @State private var models = ModelStore()
    @AppStorage("theme") private var theme = "system"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(models)
                .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
        }
    }
}

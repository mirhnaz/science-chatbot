import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(ModelStore.self) private var models
    @Environment(\.dismiss) private var dismiss
    @AppStorage("engineMode") private var engineChoice = EngineChoice.automatic.rawValue
    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("theme") private var theme = "system"
    @State private var importing = false
    @State private var connection: String?
    @AppStorage(Speech.voiceKey) private var voiceID = ""
    @State private var speech = Speech()

    var body: some View {
        @Bindable var models = models
        NavigationStack {
            Form {
                Section {
                    Picker("Answer questions using", selection: $engineChoice) {
                        ForEach(EngineChoice.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Tutor")
                } footer: {
                    Text(modeHelp)
                }

                Section {
                    if models.models.isEmpty {
                        Text("No model yet. Download one, import a .gguf file, or copy it into this app with Finder.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Model", selection: $models.selectedName) {
                            ForEach(models.models, id: \.lastPathComponent) {
                                Text($0.lastPathComponent).tag($0.lastPathComponent)
                            }
                        }
                    }
                    if let progress = models.downloadProgress {
                        ProgressView(value: progress) { Text("Downloading \(ModelStore.recommendedName)") }
                        Button("Cancel download", role: .cancel) { models.cancelDownload() }
                    } else {
                        Button("Download recommended model (2.5 GB)", systemImage: "arrow.down.circle") {
                            models.downloadRecommended()
                        }
                    }
                    Button("Import model file…", systemImage: "folder") { importing = true }
                    Button("Refresh list", systemImage: "arrow.clockwise") { models.refresh() }
                    if let message = models.message { Text(message).font(.footnote) }
                } header: {
                    Text("On this iPad (offline)")
                } footer: {
                    Text("Recommended: \(ModelStore.recommendedName). After it is on the iPad, no internet is needed.")
                }

                Section {
                    TextField(ServerAddress.builtIn ?? "https://your-pc.tailnet.ts.net", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Test connection") {
                        connection = "Checking…"
                        Task {
                            guard let remote = RemoteEngine(address: ServerAddress.effective(serverURL)) else {
                                connection = "Enter a full address starting with https://"
                                return
                            }
                            connection = await remote.checkHealth()
                                ? "Connected. The server is running."
                                : "Could not reach the server."
                        }
                    }
                    if let connection { Text(connection).font(.footnote) }
                } header: {
                    Text("My AI PC")
                } footer: {
                    Text(ServerAddress.builtIn == nil
                         ? "The Science Chatbot server address, for example your Tailscale Funnel URL."
                         : "Leave empty to use the built-in address shown above.")
                }

                Section {
                    Picker("Voice", selection: $voiceID) {
                        Text("Automatic (best installed)").tag("")
                        ForEach(Speech.voices(language: Speech.deviceLanguage), id: \.identifier) { voice in
                            Text("\(voice.name) · \(voice.quality.label) · \(voice.language)").tag(voice.identifier)
                        }
                    }
                    Button("Preview voice", systemImage: "speaker.wave.2") {
                        speech.preview(AVSpeechSynthesisVoice(identifier: voiceID))
                    }
                } header: {
                    Text("Read aloud")
                } footer: {
                    Text("For more natural voices, download a Premium or Enhanced voice in the iPad’s Settings → Accessibility → Read & Speak → Voices, then return here. Siri’s own voice is not available to apps.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
                if case .success(let url) = result { models.importModel(from: url) }
            }
            .onAppear { models.refresh() }
            .onDisappear { speech.stop() }
        }
        .tint(Palette.accent)
    }

    private var modeHelp: String {
        switch EngineChoice(rawValue: engineChoice) ?? .automatic {
        case .automatic:
            return "Uses your AI PC over the internet. Without internet (for example airplane mode), or if the PC cannot answer, uses the model on this iPad."
        case .remote:
            return "Always uses your AI PC. Needs internet."
        case .local:
            return "Always uses the model on this iPad. Works offline."
        }
    }
}

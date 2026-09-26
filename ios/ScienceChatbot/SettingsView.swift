import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Kept simple for 10–13 year olds: tutor mode and theme. Everything else is
/// on the Advanced page behind a grown-ups warning.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("engineMode") private var engineChoice = EngineChoice.automatic.rawValue
    @AppStorage("theme") private var theme = "system"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Answer questions using", selection: $engineChoice) {
                        ForEach(EngineChoice.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Tutor")
                } footer: {
                    Text(modeHelp)
                }
                .listRowBackground(Color("Surface"))

                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }
                .listRowBackground(Color("Surface"))

                Section {
                    LabeledContent("Made with love by", value: "Ayaan and Naz")
                } header: {
                    Text("About")
                }
                .listRowBackground(Color("Surface"))

                Section {
                    NavigationLink {
                        AdvancedSettingsView()
                    } label: {
                        Label("Advanced (for grown-ups)", systemImage: "exclamationmark.triangle")
                    }
                }
                .listRowBackground(Color("Surface"))
            }
            .scrollContentBackground(.hidden)
            .background(Color("Background"))
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    private var modeHelp: String {
        switch EngineChoice(rawValue: engineChoice) ?? .automatic {
        case .automatic:
            return "Uses mir-ai-pc at home. With no internet, the iPad answers by itself."
        case .remote:
            return "Always uses mir-ai-pc at home. Needs internet."
        case .local:
            return "Always answers on this iPad. Works without internet."
        }
    }
}

/// Model files, the AI PC connection check, and voices.
struct AdvancedSettingsView: View {
    @Environment(ModelStore.self) private var models
    @Environment(NaturalVoiceStore.self) private var naturalVoice
    @AppStorage(Speech.voiceKey) private var voiceID = ""
    @AppStorage(Speech.naturalKey) private var useNatural = true
    @State private var importing = false
    @State private var connection: String?
    @State private var speech = Speech()

    var body: some View {
        @Bindable var models = models
        Form {
            Section {
                Label {
                    Text("These settings are for grown-ups. If you’re not sure what something does, please don’t change it — the app might stop answering questions.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .listRowBackground(Color("Surface"))

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
            .listRowBackground(Color("Surface"))

            Section {
                LabeledContent("Address", value: ServerAddress.url ?? "Not set in this build")
                Button("Test connection") {
                    connection = "Checking…"
                    Task {
                        guard let remote = RemoteEngine(address: ServerAddress.url ?? "") else {
                            connection = "No AI PC address was built into this app."
                            return
                        }
                        connection = await remote.checkHealth()
                            ? "Connected. The server is running."
                            : "Could not reach the server."
                    }
                }
                if let connection { Text(connection).font(.footnote) }
            } header: {
                Text("mir-ai-pc")
            } footer: {
                Text("The address is built into the app (SCIENCE_SERVER_HOST in ios/Local.xcconfig).")
            }
            .listRowBackground(Color("Surface"))

            Section {
                Toggle("Natural voice (\(NaturalVoice.name))", isOn: $useNatural)
                    .disabled(!naturalVoice.isInstalled)
                if let progress = naturalVoice.progress {
                    ProgressView(value: progress) { Text("Downloading the natural voice") }
                    Button("Cancel download", role: .cancel) { naturalVoice.cancel() }
                } else if naturalVoice.isInstalled {
                    Button("Delete natural voice", systemImage: "trash", role: .destructive) {
                        speech.stop()
                        naturalVoice.delete()
                    }
                } else {
                    Button("Download natural voice (\(NaturalVoice.downloadSize))", systemImage: "arrow.down.circle") {
                        naturalVoice.download()
                    }
                }
                if let message = naturalVoice.message { Text(message).font(.footnote) }

                Picker("Apple voice", selection: $voiceID) {
                    Text("Automatic (best installed)").tag("")
                    ForEach(Speech.voices(language: Speech.deviceLanguage), id: \.identifier) { voice in
                        Text("\(voice.name) · \(voice.quality.label) · \(voice.language)").tag(voice.identifier)
                    }
                }
                Button("Preview voice", systemImage: "speaker.wave.2") {
                    speech.preview(natural: useNatural, voice: AVSpeechSynthesisVoice(identifier: voiceID))
                }
            } header: {
                Text("Read aloud")
            } footer: {
                Text("The natural voice runs on this iPad, offline, for English answers. Other languages, or no natural voice, use the Apple voice. For better Apple voices, download a Premium or Enhanced voice in the iPad’s Settings → Accessibility → Read & Speak → Voices.")
            }
            .listRowBackground(Color("Surface"))
        }
        .scrollContentBackground(.hidden)
        .background(Color("Background"))
        .navigationTitle("Advanced")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result { models.importModel(from: url) }
        }
        .onAppear { models.refresh() }
        .onDisappear { speech.stop() }
    }
}

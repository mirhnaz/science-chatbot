import ScienceCore
import SwiftUI

/// iPadOS layout: a sidebar of starter ideas and a detail column with the
/// answer. Controls live on the Liquid Glass layer (toolbar and the compose
/// bar at the bottom); content scrolls underneath. On iPhone the split view
/// collapses to one column that opens on the answer, with Ideas one tap back.
/// docs/DESIGN.md describes the same layout for the web.
struct ContentView: View {
    @Environment(ModelStore.self) private var models
    @AppStorage("engineMode") private var engineChoice = EngineChoice.automatic.rawValue
    @State private var chat = ChatModel()
    @State private var network = NetworkMonitor()
    @State private var speech = Speech()
    @State private var showSettings = false
    @State private var selectedIdea: Suggestion.ID?
    @State private var compactColumn = NavigationSplitViewColumn.detail

    private var choice: EngineChoice { EngineChoice(rawValue: engineChoice) ?? .automatic }

    /// Engines to try, in order, for the mode chosen in Settings. Empty if
    /// nothing is set up yet.
    private var engines: [TutorEngine] {
        let address = ServerAddress.url ?? ""
        let local = models.selectedPath.map(LocalTutor.init(modelPath:))
        switch choice {
        case .remote:
            return [RemoteEngine(address: address)].compactMap { $0 }
        case .local:
            return [local].compactMap { $0 }
        case .automatic:
            // Offline (for example airplane mode): skip the PC entirely.
            let remote = network.isOnline ? RemoteEngine(address: address, preflight: local != nil) : nil
            return [remote as TutorEngine?, local].compactMap { $0 }
        }
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            IdeasList(chat: chat, selection: $selectedIdea)
                .navigationTitle("Ideas")
                .toolbar {
                    ToolbarItem {
                        Button("Surprise me", systemImage: "dice") {
                            selectedIdea = nil
                            chat.surprise()
                        }
                    }
                }
        } detail: {
            AnswerView(chat: chat, speech: speech) { followUp in
                ask(followUp)
            }
            .navigationTitle("Science Chatbot")
            .navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let answer = chat.reply?.answer { speech.toggle(answer) }
                    } label: {
                        Label(speech.isSpeaking ? "Stop reading" : "Read aloud",
                              systemImage: speech.isSpeaking ? "stop.fill" : "speaker.wave.2")
                    }
                    .disabled(chat.reply == nil || chat.isLoading)
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ComposeBar(chat: chat) { ask(nil) }
            }
        }
        .onChange(of: selectedIdea) { _, id in
            // Like the web: a starter fills the box; the child presses send.
            if let idea = chat.suggestions.first(where: { $0.id == id }) {
                chat.question = idea.question
                compactColumn = .detail
            }
        }
        .onChange(of: chat.isLoading) { _, loading in if loading { speech.stop() } }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func ask(_ text: String?) {
        selectedIdea = nil
        chat.ask(text, using: engines)
    }

    /// Only what a child needs: working, offline, or not set up.
    private var subtitle: String {
        if chat.isLoading { return "Thinking…" }
        guard let first = engines.first else { return "Not set up yet" }
        return first is RemoteEngine ? "" : "Offline mode"
    }
}

/// Starter ideas in the sidebar, like "Need a spark?" on the web.
struct IdeasList: View {
    let chat: ChatModel
    @Binding var selection: Suggestion.ID?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(chat.suggestions) { idea in
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(idea.topic).font(.caption).foregroundStyle(.secondary)
                            Text(idea.question)
                        }
                        .padding(.vertical, 4)
                    } icon: {
                        Text(idea.icon)
                    }
                    .tag(idea.id)
                    .accessibilityHint("Puts this question in the question box")
                }
            } header: {
                Text("Need a spark?")
            } footer: {
                Text("Pick an idea, or tap the dice for new ones.")
            }
        }
        .listStyle(.sidebar)
    }
}

/// The answer column: empty state, progress, error, or the reply with its
/// follow-up questions. Kept to a readable width like a book page.
struct AnswerView: View {
    let chat: ChatModel
    let speech: Speech
    let askFollowUp: (String) -> Void

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var content: some View {
        if chat.isLoading {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Working on your answer…").font(.headline)
                Text("The first question can take a little longer.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 360)
        } else if let error = chat.errorText {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.1), in: .rect(cornerRadius: 16))
        } else if let reply = chat.reply {
            VStack(alignment: .leading, spacing: 16) {
                Text(chat.askedQuestion)
                    .font(.title2.bold())
                    .foregroundStyle(.tint)
                Text(reply.answer)
                    .font(.title3)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                FollowUps(questions: reply.followUps, ask: askFollowUp)
                    .padding(.top, 12)
            }
        } else {
            EmptyState()
        }
    }
}

/// "Keep exploring": tappable rows with chevrons, like an inset grouped list.
struct FollowUps: View {
    let questions: [String]
    let ask: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keep exploring").font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    if index > 0 { Divider().padding(.leading, 16) }
                    Button {
                        ask(question)
                    } label: {
                        HStack(spacing: 12) {
                            Text(question).multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 16))
        }
    }
}

/// The question box on the glass layer, pinned above the keyboard.
struct ComposeBar: View {
    @Bindable var chat: ChatModel
    let send: () -> Void
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !chat.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask a science question…", text: $chat.question, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .submitLabel(.send)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
                    .accessibilityLabel("Your science question")
                    .onChange(of: chat.question) { _, text in
                        // Return sends, like Messages; a vertical field would
                        // otherwise insert a new line.
                        if text.contains("\n") {
                            chat.question = text.replacingOccurrences(of: "\n", with: "")
                            if canSend, !chat.isLoading { submit() }
                        } else if text.utf16.count > maxQuestionLength {
                            chat.question = String(text.utf16.prefix(maxQuestionLength)) ?? text
                        }
                    }

                if chat.isLoading {
                    Button("Stop", systemImage: "stop.fill") { chat.cancel() }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                } else {
                    Button("Ask", systemImage: "arrow.up") { submit() }
                        .labelStyle(.iconOnly)
                        .font(.title3.bold())
                        .frame(width: 48, height: 48)
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .disabled(!canSend)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func submit() {
        focused = false
        send()
    }
}

/// Shown before the first question: the one place the brand mark appears.
struct EmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .clipShape(.rect(cornerRadius: 26))
                .accessibilityHidden(true)
            Text("A little curiosity.\nA whole world to explore.")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Ask a question below, or pick an idea.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

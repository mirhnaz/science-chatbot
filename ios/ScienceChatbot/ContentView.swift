import ScienceCore
import SwiftUI

/// The curiosity column (docs/DESIGN.md, docs/design/curiosity-column.png).
///
/// One column, no sidebar. A fresh session centres the question box with
/// starter ideas; after the first question the box moves to the bottom and
/// the trail (one topic's chain of questions) grows above it. "Dive deeper"
/// follow-ups sit under the latest answer; "try something new" chips sit
/// above the question box and start a new trail. Controls (toolbar, chips,
/// question box) are on Liquid Glass; the trail scrolls beneath.
struct ContentView: View {
    @Environment(ModelStore.self) private var models
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("engineMode") private var engineChoice = EngineChoice.automatic.rawValue
    @State private var chat = ChatModel()
    @State private var network = NetworkMonitor()
    @State private var speech = Speech()
    @State private var speakingStep: UUID?
    @State private var showSettings = false
    @FocusState private var composing: Bool
    @Namespace private var glide

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

    private var fresh: Bool { chat.steps.isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if fresh {
                    FreshSession(chat: chat, start: startTrail, edit: edit) {
                        compose.matchedGeometryEffect(id: "compose", in: glide)
                    }
                    .transition(.opacity)
                } else {
                    TrailView(chat: chat, speakingStep: speakingStep,
                              speak: toggleSpeech, dive: { text in continueTrail { chat.ask(text, using: engines) } },
                              editFollowUp: edit, retry: { continueTrail { chat.retry(using: engines) } })
                        // A safe-area *bar*: the system keeps the trail clear
                        // of the dock and fades/blurs it as it scrolls beneath,
                        // like the toolbar. (Measuring the dock by hand caused
                        // a layout loop; a plain inset let text clash with it.)
                        .safeAreaBar(edge: .bottom) {
                            VStack(spacing: 0) {
                                SomethingNew(chat: chat, askOwn: askOwn, start: startTrail)
                                compose.matchedGeometryEffect(id: "compose", in: glide)
                            }
                            .frame(maxWidth: 720)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.2), value: fresh)
            .overlay(alignment: .top) {
                if chat.undoSteps != nil {
                    UndoBanner(undo: { chat.undo() }, expire: { chat.clearUndo() })
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: chat.undoSteps != nil)
            .navigationTitle(chat.steps.first?.question ?? "Science Chatbot")
            .navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(subtitle)
            .toolbar {
                // The brand mark stays visible once a trail starts (the fresh
                // screen shows the large one). Plain, not a glass button.
                if !fresh {
                    ToolbarItem(placement: .topBarLeading) {
                        BrandMark(size: 34)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
            }
        }
        .onChange(of: chat.isLoading) { _, loading in if loading { stopSpeech() } }
        .onChange(of: speech.isSpeaking) { _, speaking in if !speaking { speakingStep = nil } }
        .sheet(isPresented: $showSettings) { SettingsView() }
        #if DEBUG
        .task {
            // Debug builds only: `-autoAsk` asks the first spark, then a
            // follow-up, so layouts can be checked without tapping.
            guard ProcessInfo.processInfo.arguments.contains("-autoAsk"),
                  let idea = chat.suggestions.first else { return }
            try? await Task.sleep(for: .seconds(2))
            startTrail(idea)
            while chat.isLoading { try? await Task.sleep(for: .milliseconds(300)) }
            try? await Task.sleep(for: .seconds(1))
            if let next = chat.steps.last?.reply?.followUps.first { continueTrail { chat.ask(next, using: engines) } }
            // `-autoAskOwn`: then tap "Ask your own" to open an empty trail.
            guard ProcessInfo.processInfo.arguments.contains("-autoAskOwn") else { return }
            while chat.isLoading { try? await Task.sleep(for: .milliseconds(300)) }
            try? await Task.sleep(for: .seconds(2))
            askOwn()
        }
        #endif
    }

    /// The one question box. It moves between the centre (fresh session) and
    /// the bottom (trail), which shows children where questions go.
    private var compose: some View {
        ComposeBar(chat: chat, focused: $composing,
                   placeholder: fresh ? "Ask a science question…" : "Ask more about this…") {
            continueTrail { chat.ask(using: engines) }
        }
    }

    /// Only what a child needs: working, offline, not set up, or trail length.
    private var subtitle: String {
        if chat.isLoading { return "Thinking…" }
        guard let first = engines.first else { return "Not set up yet" }
        if !(first is RemoteEngine) { return "Offline mode" }
        return chat.steps.count > 1 ? "\(chat.steps.count) steps" : ""
    }

    /// Adds a step to the trail inside the same smooth animation that folds
    /// the previous step and scrolls to the new one.
    private func continueTrail(_ change: () -> Void) {
        withAnimation(trailAnimation(reduceMotion), change)
    }

    private func startTrail(_ idea: Suggestion) {
        stopSpeech()
        chat.startTrail(with: idea, using: engines)
    }

    private func askOwn() {
        stopSpeech()
        chat.startEmptyTrail()
        // No automatic keyboard: it would hide the Sparks. The question box
        // is centred and ready to tap.
        composing = false
    }

    /// Long-press "Edit before asking": fills the box instead of asking.
    private func edit(_ text: String) {
        chat.question = text
        composing = true
    }

    private func toggleSpeech(_ step: TrailStep) {
        guard let answer = step.reply?.answer else { return }
        if speakingStep == step.id {
            stopSpeech()
        } else {
            speech.stop()
            speech.toggle(answer)
            speakingStep = step.id
        }
    }

    private func stopSpeech() {
        speech.stop()
        speakingStep = nil
    }
}

// MARK: Fresh session

/// A fresh session: hero, the question box, and starter ideas, centred.
/// Scrolls if the screen is short (small windows, large text, keyboard).
struct FreshSession<Compose: View>: View {
    let chat: ChatModel
    let start: (Suggestion) -> Void
    let edit: (String) -> Void
    @ViewBuilder let compose: Compose
    /// Visible height of the scroll view (without toolbar and keyboard).
    @State private var visibleHeight = 0.0

    var body: some View {
        ScrollView {
            // At least as tall as the screen and centred with spacers, so when
            // it fits there is nothing to scroll and it can never be left
            // scrolled up (`defaultScrollAnchor` only centres once, and the
            // switch from a trail left it offset).
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Hero()
                compose
                StarterIdeas(chat: chat, start: start, edit: edit)
                MadeWithLove()
                    .padding(.top, 28)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, minHeight: visibleHeight)
        }
        // The scroll view's own size does not depend on its content, so
        // measuring it cannot loop.
        .onGeometryChange(for: Double.self) { proxy in
            proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom
        } action: { visibleHeight = max($0, 0) }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// The app icon as a decorative mark, with iOS-style rounded corners.
struct BrandMark: View {
    var size: CGFloat

    var body: some View {
        Image("BrandIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.225))
            .accessibilityHidden(true)
    }
}

/// "❤️ Made with love by Ayaan and Naz".
struct MadeWithLove: View {
    var body: some View {
        Text("❤️ Made with love by **Ayaan and Naz**")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// Shown before the first question, with the large brand mark.
struct Hero: View {
    var body: some View {
        VStack(spacing: 16) {
            BrandMark(size: 96)
            Text("A little curiosity.\nA whole world to explore.")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 24)
    }
}

/// "Sparks": four starter ideas that each start a trail when tapped.
struct StarterIdeas: View {
    let chat: ChatModel
    let start: (Suggestion) -> Void
    let edit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sparks").font(.headline)
                Text("Pick one to start exploring").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.leading, 6)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                ForEach(chat.suggestions) { idea in
                    Button { start(idea) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(idea.icon) \(idea.topic)").font(.footnote).foregroundStyle(.secondary)
                            Text(idea.question).font(.body).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                        .padding(14)
                        .background(.background.secondary, in: .rect(cornerRadius: 16))
                        .contentShape(.rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .contextMenu {
                        Button("Edit before asking", systemImage: "pencil") { edit(idea.question) }
                    }
                    .accessibilityHint("Asks this question")
                }
            }
            Button("New sparks", systemImage: "dice") { chat.surprise() }
                .buttonStyle(.glass)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .padding(.top, 20)
    }
}

// MARK: Dock

/// "New spark": starts a new trail. Sits just above the question box.
struct SomethingNew: View {
    let chat: ChatModel
    let askOwn: () -> Void
    let start: (Suggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("New spark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.leading, 6)
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Ask your own", systemImage: "square.and.pencil", action: askOwn)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                            .keyboardShortcut("n", modifiers: .command)
                        Button("New sparks", systemImage: "dice") { chat.surprise() }
                            .labelStyle(.iconOnly)
                        ForEach(chat.suggestions.prefix(3)) { idea in
                            Button { start(idea) } label: {
                                Text("\(idea.icon) \(idea.question)")
                                    .lineLimit(1)
                                    .frame(maxWidth: 260)
                            }
                            .accessibilityLabel(idea.question)
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(chat.isLoading)
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, 10)
    }
}

/// The question box on the glass layer, with a round send (or stop) button.
struct ComposeBar: View {
    @Bindable var chat: ChatModel
    var focused: FocusState<Bool>.Binding
    let placeholder: String
    let send: () -> Void

    private var canSend: Bool {
        !chat.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(placeholder, text: $chat.question, axis: .vertical)
                    .lineLimit(1...5)
                    .focused(focused)
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
    }

    private func submit() {
        focused.wrappedValue = false
        send()
    }
}

/// "Started a new trail · Undo", for a few seconds after something new.
struct UndoBanner: View {
    let undo: () -> Void
    let expire: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("Started a new trail")
            Button("Undo", action: undo).fontWeight(.semibold)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: .capsule)
        .task {
            try? await Task.sleep(for: .seconds(6))
            expire()
        }
    }
}

// MARK: Trail

/// The steps of the current trail. Only the latest is open; earlier ones fold
/// to their question, a preview, and the follow-up the child chose.
struct TrailView: View {
    let chat: ChatModel
    let speakingStep: UUID?
    let speak: (TrailStep) -> Void
    let dive: (String) -> Void
    let editFollowUp: (String) -> Void
    let retry: () -> Void
    @State private var expanded: Set<UUID> = []
    @State private var position = ScrollPosition(idType: UUID.self)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            // A plain VStack, not a lazy one: trails are short, and exact
            // heights let the scroll to a new step glide instead of jump.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(chat.steps) { step in
                    let latest = step.id == chat.steps.last?.id
                    Group {
                        if latest || expanded.contains(step.id) {
                            OpenStep(step: step, latest: latest, first: step.id == chat.steps.first?.id,
                                     speaking: speakingStep == step.id, speak: { speak(step) },
                                     dive: dive, editFollowUp: editFollowUp, retry: retry,
                                     fold: latest ? nil : { withAnimation(.smooth) { _ = expanded.remove(step.id) } })
                        } else {
                            FoldedStep(step: step) { withAnimation(.smooth) { _ = expanded.insert(step.id) } }
                        }
                    }
                    .id(step.id)
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .onChange(of: chat.steps.last?.id) { _, id in
            guard let id else { return }
            // Fold the earlier steps and glide to the new one together, so
            // the page does not shift under the scroll.
            withAnimation(trailAnimation(reduceMotion)) {
                expanded = []
                position.scrollTo(id: id, anchor: .top)
            }
        }
    }
}

/// The animation for adding a step: a smooth glide, or a short fade-like
/// ease when Reduce Motion is on.
func trailAnimation(_ reduceMotion: Bool) -> Animation {
    reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.55)
}

/// An earlier step: question, two-line preview, and the chosen follow-up.
struct FoldedStep: View {
    let step: TrailStep
    let expand: () -> Void

    var body: some View {
        Button(action: expand) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(step.question).font(.headline).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                if let answer = step.reply?.answer {
                    Text(answer).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let chosen = step.chosen {
                    Label(chosen, systemImage: "arrow.turn.down.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.background, in: .capsule)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows this answer again")
    }
}

/// The latest step (or an earlier one the child re-opened).
struct OpenStep: View {
    let step: TrailStep
    let latest: Bool
    let first: Bool
    let speaking: Bool
    let speak: () -> Void
    let dive: (String) -> Void
    let editFollowUp: (String) -> Void
    let retry: () -> Void
    let fold: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if first, let topic = step.topic {
                Text(topic).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(step.question).font(.title2.bold()).foregroundStyle(.tint)
                Spacer(minLength: 8)
                if step.reply != nil {
                    Button(speaking ? "Stop reading" : "Read aloud",
                           systemImage: speaking ? "speaker.wave.3.fill" : "speaker.wave.2") { speak() }
                        .labelStyle(.iconOnly)
                        // Waves pulse while reading; tap again to stop.
                        .symbolEffect(.variableColor.iterative, isActive: speaking)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                }
                if let fold {
                    Button("Fold", systemImage: "chevron.up", action: fold)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }

            if step.isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Working on your answer…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            } else if let error = step.error {
                VStack(alignment: .leading, spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    if latest {
                        Button("Try again", systemImage: "arrow.clockwise", action: retry)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.08), in: .rect(cornerRadius: 16))
            } else if let reply = step.reply {
                Text(reply.answer)
                    .font(.title3)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                if latest {
                    DiveDeeper(questions: reply.followUps, ask: dive, edit: editFollowUp)
                        .padding(.top, 8)
                } else if let chosen = step.chosen {
                    Label(chosen, systemImage: "arrow.turn.down.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
        .padding(.bottom, 8)
    }
}

/// "Dive deeper": the latest answer's follow-ups, in the accent colour.
struct DiveDeeper: View {
    let questions: [String]
    let ask: (String) -> Void
    let edit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dive deeper").font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    if index > 0 { Divider().overlay(Color.accentColor.opacity(0.15)).padding(.leading, 16) }
                    Button { ask(question) } label: {
                        HStack(spacing: 12) {
                            Text(question).multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).opacity(0.55)
                        }
                        .foregroundStyle(.tint)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .contextMenu {
                        Button("Edit before asking", systemImage: "pencil") { edit(question) }
                    }
                }
            }
            .background(Color.accentColor.opacity(0.09), in: .rect(cornerRadius: 16))
        }
    }
}

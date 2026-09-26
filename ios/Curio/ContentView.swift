import ScienceCore
import SwiftUI

/// The 2026-09 redesign (docs/design/redesign-2026-09/): Home, then a Trail
/// of up to `ChatModel.trailLength` steps. Leaving a trail keeps it, and Home
/// offers to continue it. Each screen draws its own header on the warm ground.
struct ContentView: View {
    enum Screen { case home, trail }

    @Environment(ModelStore.self) private var models
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("engineMode") private var engineChoice = EngineChoice.automatic.rawValue
    @State private var chat = ChatModel()
    @State private var network = NetworkMonitor()
    @State private var speech = Speech()
    @State private var speakingStep: UUID?
    @State private var showSettings = false
    @State private var screen = Screen.home
    @FocusState private var composing: Bool

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
        NavigationStack {
            Group {
                switch screen {
                case .home:
                    HomeView(chat: chat, resume: { go(.trail) }, start: startTrail, edit: edit,
                             openSettings: { showSettings = true })
                        .safeAreaBar(edge: .bottom) { bar(placeholder: "Ask anything…", send: askFromHome) }
                        .toolbar(.hidden, for: .navigationBar)
                        .transition(.opacity)
                case .trail:
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
                                bar(placeholder: "Ask more about this…") {
                                    continueTrail { chat.ask(using: engines) }
                                }
                            }
                        }
                        .navigationTitle(chat.steps.first?.question ?? "Curio")
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationSubtitle(subtitle)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Home", systemImage: "chevron.left") { go(.home) }
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Button("Settings", systemImage: "gearshape") { showSettings = true }
                            }
                        }
                        .transition(.opacity)
                }
            }
            .background(Curio.ground)
            .overlay(alignment: .top) {
                if chat.undoSteps != nil {
                    UndoBanner(undo: { chat.undo() }, expire: { chat.clearUndo() })
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: chat.undoSteps != nil)
        }
        .onChange(of: chat.isLoading) { _, loading in if loading { stopSpeech() } }
        .onChange(of: speech.isSpeaking) { _, speaking in if !speaking { speakingStep = nil } }
        .onChange(of: chat.steps.isEmpty) { _, empty in if empty { go(.home) } }
        .sheet(isPresented: $showSettings) { SettingsView() }
        #if DEBUG
        .task {
            // Debug builds only: `-autoAsk` asks the first spark, then a
            // follow-up, so layouts can be checked without tapping.
            // `-autoHome` then returns Home to show the resume card.
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("-autoAsk"), let idea = chat.suggestions.first else { return }
            try? await Task.sleep(for: .seconds(2))
            startTrail(idea)
            while chat.isLoading { try? await Task.sleep(for: .milliseconds(300)) }
            try? await Task.sleep(for: .seconds(1))
            if let next = chat.steps.last?.reply?.followUps.first { continueTrail { chat.ask(next, using: engines) } }
            guard arguments.contains("-autoHome") else { return }
            while chat.isLoading { try? await Task.sleep(for: .milliseconds(300)) }
            try? await Task.sleep(for: .seconds(2))
            go(.home)
        }
        #endif
    }

    /// The bottom bar, at the readable width on iPad.
    private func bar(placeholder: String, send: @escaping () -> Void) -> some View {
        BottomBar(chat: chat, focused: $composing, placeholder: placeholder, send: send)
            .frame(maxWidth: 720)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    /// Only what a child needs: working, offline, not set up, or trail length.
    private var subtitle: String {
        if chat.isLoading { return "Thinking…" }
        guard let first = engines.first else { return "Not set up yet" }
        if !(first is RemoteEngine) { return "Offline mode" }
        return chat.steps.count > 1 ? "\(chat.steps.count) steps" : ""
    }

    private func go(_ next: Screen) {
        guard next != screen else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35)) { screen = next }
    }

    /// Adds a step to the trail inside the same smooth animation that folds
    /// the previous step and scrolls to the new one.
    private func continueTrail(_ change: () -> Void) {
        withAnimation(trailAnimation(reduceMotion), change)
    }

    private func startTrail(_ idea: Suggestion) {
        stopSpeech()
        chat.startTrail(with: idea, using: engines)
        go(.trail)
    }

    /// A question typed on Home starts a new trail (Undo brings back the old).
    private func askFromHome() {
        stopSpeech()
        let typed = chat.question
        chat.startEmptyTrail()
        chat.ask(typed, using: engines)
        go(.trail)
    }

    private func askOwn() {
        stopSpeech()
        chat.startEmptyTrail()
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
    private static let content = "trailContent"
    private static let topPadding = 12.0
    let chat: ChatModel
    let speakingStep: UUID?
    let speak: (TrailStep) -> Void
    let dive: (String) -> Void
    let editFollowUp: (String) -> Void
    let retry: () -> Void
    @State private var expanded: Set<UUID> = []
    @State private var position = ScrollPosition(idType: UUID.self)
    /// Height of the trail's scroll view; the latest step reserves this much
    /// so the scroll can reach it (the dock's inset adds no scroll room).
    @State private var visibleHeight = 0.0
    /// Top of the latest step inside the trail content (not affected by
    /// scrolling), used to scroll that step to the top.
    @State private var latestTop = 0.0
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
                    // The latest step reserves a screen's height, so its
                    // question can scroll to the top and the answer fills in
                    // below it in view (the end of the content would
                    // otherwise stop the scroll short).
                    .frame(minHeight: latest ? visibleHeight : nil, alignment: .top)
                    .onGeometryChange(for: Double.self) { proxy in
                        proxy.frame(in: .named(Self.content)).minY
                    } action: { top in
                        if latest { latestTop = top }
                    }
                    .id(step.id)
                }
            }
            .coordinateSpace(.named(Self.content))
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, Self.topPadding)
            .frame(maxWidth: .infinity)
        }
        // The scroll view's own size, not its content: cannot loop.
        .onGeometryChange(for: Double.self) { proxy in
            proxy.size.height
        } action: { visibleHeight = $0 }
        .scrollPosition($position)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .onChange(of: chat.steps.last?.id) { _, id in
            guard id != nil else { return }
            // First fold the earlier steps, then glide the new question to the
            // top. A scroll asked for while the fold is still animating is
            // dropped by SwiftUI, so the glide waits for it to settle.
            let fold = reduceMotion ? 0.15 : 0.3
            withAnimation(.smooth(duration: fold)) { expanded = [] }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(fold + 0.05))
                withAnimation(trailAnimation(reduceMotion)) {
                    // latestTop is measured inside the padded content.
                    position.scrollTo(y: latestTop + Self.topPadding - 8)
                }
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
                if let seconds = step.seconds {
                    // Shows unusual delays at a glance; names the iPad when
                    // it answered offline instead of mir-ai-pc.
                    Text(answeredLabel(seconds: seconds, source: step.source))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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

/// "Answered in 3.2 seconds", plus "· on this iPad" for offline answers.
func answeredLabel(seconds: Double, source: String?) -> String {
    let time = String(format: "Answered in %.1f seconds", seconds)
    return source == EngineChoice.local.label ? "\(time) · on this iPad" : time
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

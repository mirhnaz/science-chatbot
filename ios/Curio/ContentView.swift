import ScienceCore
import SwiftUI

/// The 2026-09 redesign (docs/design/redesign-2026-09/): Home, then a Trail
/// of up to `ChatModel.trailLength` steps. Leaving a trail keeps it, and Home
/// offers to continue it. Each screen draws its own header on the warm ground.
struct ContentView: View {
    enum Screen { case home, trail, complete }

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
    @State private var stamps = StampStore(persists: !ProcessInfo.processInfo.arguments.contains("-autoAsk"))
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
                    TrailView(chat: chat, speakingStep: speakingStep, speak: toggleSpeech,
                              dive: { text in continueTrail { chat.ask(text, using: engines) } },
                              editFollowUp: edit, retry: { continueTrail { chat.retry(using: engines) } },
                              finish: finishTrail)
                        .safeAreaBar(edge: .top) {
                            TrailHeader(title: chat.topic ?? "Your question", detail: trailDetail,
                                        back: { go(.home) }, settings: { showSettings = true })
                        }
                        // A safe-area *bar*: the system keeps the trail clear
                        // of the question box and fades it as it scrolls
                        // beneath. (Measuring the bar by hand caused a layout
                        // loop; a plain inset let text clash with it.) The
                        // last step offers Finish instead.
                        .safeAreaBar(edge: .bottom) {
                            if !chat.isComplete {
                                bar(placeholder: "Ask more about \(chat.topic?.lowercased() ?? "this")…") {
                                    continueTrail { chat.ask(using: engines) }
                                }
                            }
                        }
                        .toolbar(.hidden, for: .navigationBar)
                        .transition(.opacity)
                case .complete:
                    CompleteView(chat: chat, stamps: stamps, close: { go(.home) }, newSpark: { go(.home) })
                        .toolbar(.hidden, for: .navigationBar)
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
            if arguments.contains("-autoComplete") {
                // Follows the first Dive deeper choice to the end, then finishes.
                while !chat.isComplete {
                    while chat.isLoading { try? await Task.sleep(for: .milliseconds(300)) }
                    try? await Task.sleep(for: .seconds(1))
                    guard !chat.isComplete, let next = chat.steps.last?.reply?.followUps.first else { break }
                    continueTrail { chat.ask(next, using: engines) }
                }
                if chat.isComplete { finishTrail() }
                return
            }
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

    /// "Trail · Step 3", or what is happening while it matters.
    private var trailDetail: String {
        if chat.isLoading { return "Thinking…" }
        if engines.isEmpty { return "Not set up yet" }
        return "Trail · Step \(chat.steps.count)"
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

    /// The last step's Finish: earns the trail's stamp once and celebrates.
    private func finishTrail() {
        stopSpeech()
        stamps.award(trail: chat.trailID, topic: chat.topic, question: chat.steps.first?.question ?? "")
        chat.markFinished()
        go(.complete)
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

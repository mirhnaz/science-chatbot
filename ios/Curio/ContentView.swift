import ScienceCore
import SwiftUI

/// The 2026-09 redesign (docs/design/redesign-2026-09/): Home, then a Trail
/// of up to `ChatModel.trailLength` steps. Leaving a trail keeps it, and Home
/// offers to continue it. Each screen draws its own header on the warm ground.
struct ContentView: View {
    /// Home is the root; Trail and Trail complete are pushed on top, so the
    /// system back swipe returns Home.
    enum Screen: Hashable { case home, trail, complete, stamps }

    @Environment(ModelStore.self) private var models
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("engineMode") private var engineChoice = EngineChoice.automatic.rawValue
    // Debug `-autoAsk` runs must not replace a child's saved trail.
    @State private var chat = ChatModel(persists: !ProcessInfo.processInfo.arguments.contains("-autoAsk"))
    @State private var network = NetworkMonitor()
    @State private var speech = Speech()
    @State private var voice = VoiceInput()
    @State private var speakingStep: UUID?
    @State private var showSettings = false
    @State private var path: [Screen] = []
    /// First launch: the welcome, once (see `offerWelcome`).
    @AppStorage("welcomed") private var welcomed = false
    @AppStorage("childName") private var childName = ""
    @State private var showWelcome = false
    /// At least 1100 pt wide: the two-column iPad layouts.
    @State private var wide = false
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

    private var screen: Screen { path.last ?? .home }

    var body: some View {
        NavigationStack(path: $path) {
            home
                .navigationDestination(for: Screen.self) { destination in
                    switch destination {
                    case .home: home
                    case .trail: trail
                    case .complete: complete
                    case .stamps:
                        StampsView(stamps: stamps, back: { go(.home) })
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
        }
        .environment(\.curioWide, wide)
        .onGeometryChange(for: Bool.self) { $0.size.width >= 1100 } action: { wide = $0 }
        .onChange(of: wide, initial: true) { _, wide in chat.sparkCount = wide ? 6 : 4 }
        .onAppear(perform: offerWelcome)
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeView {
                welcomed = true
                showWelcome = false
            }
        }
        .onChange(of: stamps.stamps.count, initial: true) { chat.uncollectedTopics = stamps.uncollectedTopics }
        .onChange(of: chat.isLoading) { _, loading in if loading { stopSpeech() } }
        .onChange(of: speech.isSpeaking) { _, speaking in if !speaking { speakingStep = nil } }
        .onChange(of: chat.steps.isEmpty) { _, empty in if empty { go(.home) } }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("Ask out loud", isPresented: Binding(get: { voice.problem != nil }, set: { if !$0 { voice.problem = nil } })) {
            Button("OK") { voice.problem = nil }
        } message: {
            Text(voice.problem ?? "")
        }
        // Leaving a screen, or an answer starting, ends listening.
        .onChange(of: screen) { voice.stop() }
        .onChange(of: chat.isLoading) { _, loading in if loading { voice.stop() } }
        #if DEBUG
        .task {
            // Debug builds only: `-autoAsk` asks the first spark, then a
            // follow-up, so layouts can be checked without tapping.
            // `-autoHome` then returns Home to show the resume card.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-removeFinishedTrails") { stamps.removeFinishedTrails() }
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

    private var home: some View {
        HomeView(chat: chat, stamps: stamps, resume: resume, start: startTrail, edit: edit,
                 openSettings: { showSettings = true }, openStamps: { go(.stamps) })
            .safeAreaBar(edge: .bottom) {
                // Wide: under the Sparks column (40 + 380 + 32 pt in).
                bar(placeholder: "Ask anything…", leading: wide ? 452 : nil, send: askFromHome)
            }
            .toolbar(.hidden, for: .navigationBar)
    }

    private var trail: some View {
        TrailView(chat: chat, speakingStep: speakingStep, speak: toggleSpeech,
                  dive: { text in continueTrail { chat.ask(text, using: engines) } },
                  editFollowUp: edit, retry: { continueTrail { chat.retry(using: engines) } },
                  finish: finishTrail, back: { go(.home) })
            .safeAreaBar(edge: .top) {
                // Wide layouts show the trail in the side rail instead.
                if !wide {
                    TrailHeader(title: chat.trailName ?? "Your question", detail: trailDetail,
                                back: { go(.home) }, settings: { showSettings = true })
                }
            }
            // A safe-area *bar*: the system keeps the trail clear of the
            // question box and fades it as it scrolls beneath. (Measuring the
            // bar by hand caused a layout loop; a plain inset let text clash
            // with it.) The last step offers Finish instead.
            .safeAreaBar(edge: .bottom) {
                if !chat.isComplete {
                    bar(placeholder: "Ask more about \(chat.trailName?.lowercased() ?? "this")…",
                        leading: wide ? 380 : nil) {
                        continueTrail { chat.ask(using: engines) }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(Curio.ground)
    }

    private var complete: some View {
        CompleteView(chat: chat, stamps: stamps, close: { go(.home) }, newSpark: { go(.home) })
            .toolbar(.hidden, for: .navigationBar)
    }

    /// The bottom bar: centred at the readable width, or, on wide layouts,
    /// under the main column from `leading` to 40 pt from the edge.
    @ViewBuilder
    private func bar(placeholder: String, leading: CGFloat? = nil, send: @escaping () -> Void) -> some View {
        let box = BottomBar(chat: chat, focused: $composing, placeholder: placeholder, voice: voice,
                            beforeListening: stopSpeech, send: send)
        if let leading {
            box.padding(.leading, leading).padding(.trailing, 40).padding(.bottom, 12)
        } else {
            box.frame(maxWidth: 720).padding(.horizontal, 20).padding(.bottom, 8)
        }
    }

    /// "Trail · Step 3", or what is happening while it matters.
    private var trailDetail: String {
        if chat.isLoading { return "Thinking…" }
        if engines.isEmpty { return "Not set up yet" }
        return "Trail · Step \(chat.steps.count)"
    }

    /// Shows the welcome on first launch, unless this device already has a
    /// name, a stamp or a saved trail (Curio was used before the welcome
    /// existed), or for Debug test runs.
    private func offerWelcome() {
        guard !welcomed else { return }
        let autoRun = ProcessInfo.processInfo.arguments.contains("-autoAsk")
        if childName.isEmpty && stamps.stamps.isEmpty && chat.openTrails.isEmpty && !autoRun {
            showWelcome = true
        } else {
            welcomed = true
        }
    }

    /// Home clears the stack; Trail and Trail complete each sit directly on
    /// Home, so going back from either returns Home.
    private func go(_ next: Screen) {
        guard next != screen else { return }
        path = next == .home ? [] : [next]
    }

    /// "Continue your trail" (or an earlier trail's row) on Home.
    private func resume(_ id: UUID) {
        stopSpeech()
        if id != chat.trailID || !chat.hasUnfinishedTrail { chat.reopen(id) }
        go(.trail)
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

    /// A question typed on Home starts a new trail; an unfinished one is kept
    /// for Home.
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

/// Keeps the system back swipe working on screens that hide the navigation
/// bar (Trail and Trail complete draw their own Back and Close buttons).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

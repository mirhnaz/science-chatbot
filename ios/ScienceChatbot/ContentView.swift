import ScienceCore
import SwiftUI

/// Two panels side by side on iPad (like the web workspace); stacked on
/// iPhone or narrow Split View, like the web's small-screen layout.
struct ContentView: View {
    @Environment(ModelStore.self) private var models
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("engineMode") private var engineChoice = EngineChoice.automatic.rawValue
    @State private var chat = ChatModel()
    @State private var network = NetworkMonitor()
    @State private var showSettings = false

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
        VStack(spacing: 0) {
            header
            if sizeClass == .regular {
                // Same split as the web's `.9fr 1.2fr` grid. `layoutPriority`
                // cannot do this: it hands all spare width to one panel.
                GeometryReader { proxy in
                    let spacing = 18.0
                    let width = max(proxy.size.width - spacing, 0)
                    HStack(alignment: .top, spacing: spacing) {
                        QuestionPanel(chat: chat, engines: engines, scrolls: true)
                            .frame(width: width * 0.9 / 2.1)
                        AnswerPanel(chat: chat, engines: engines)
                            .frame(width: width * 1.2 / 2.1)
                    }
                }
                .padding([.horizontal, .bottom], 24)
                .padding(.top, 8)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        QuestionPanel(chat: chat, engines: engines)
                        AnswerPanel(chat: chat, engines: engines).frame(minHeight: 460)
                    }
                    .padding(16)
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .tint(Palette.accent)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    /// A plain header row like the web's compact masthead. Toolbar items would
    /// be squeezed into separate glass bubbles on iPadOS 26.
    private var header: some View {
        HStack(spacing: 12) {
            Brand()
            Spacer(minLength: 12)
            Label(engineBadge, systemImage: badgeIcon)
                .labelStyle(.titleAndIcon)
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, sizeClass == .regular ? 24 : 16)
        .padding(.top, 8)
    }

    /// Names the engine that will be tried first.
    private var engineBadge: String {
        guard let first = engines.first else { return "\(choice.label) · not set up" }
        return choice == .automatic ? "Automatic · \(first.name)" : first.name
    }

    private var badgeIcon: String {
        engines.first is RemoteEngine ? "desktopcomputer" : "ipad"
    }
}

/// The web masthead: icon, name with a star, and tagline.
struct Brand: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("BrandIcon").resizable().frame(width: 36, height: 36)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                (Text("Science Chatbot ").font(.headline) + Text("✦").font(.subheadline).foregroundColor(Palette.accent))
                    .foregroundStyle(Palette.ink)
                Text("Big questions. Everyday discoveries.").font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct QuestionPanel: View {
    @Bindable var chat: ChatModel
    let engines: [TutorEngine]
    /// True in the two-panel layout: scroll inside the panel instead of
    /// growing taller than the screen.
    var scrolls = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }.scrollBounceBehavior(.basedOnSize)
            } else {
                content
            }
        }
        .panel()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("01 / START WITH A WONDER")
                Text("What makes you curious?").font(.title2.bold()).foregroundStyle(Palette.ink)
            }

            TextField("Why does the Moon change shape?", text: $chat.question, axis: .vertical)
                .lineLimit(3...6)
                .focused($focused)
                .submitLabel(.send)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Palette.input, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? Palette.accent : Palette.line))
                .accessibilityLabel("Your science question")
                .onChange(of: chat.question) { _, text in
                    if text.utf16.count > maxQuestionLength {
                        chat.question = String(text.utf16.prefix(maxQuestionLength)) ?? text
                    }
                }

            HStack(spacing: 10) {
                Button {
                    focused = false
                    chat.ask(using: engines)
                } label: {
                    Label("Ask a question", systemImage: "arrow.up.right")
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.primaryButton)
                .disabled(chat.isLoading)
                .keyboardShortcut(.return, modifiers: .command)

                if chat.isLoading {
                    Button("Stop") { chat.cancel() }.buttonStyle(SecondaryButtonStyle())
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Need a spark?").font(.headline).foregroundStyle(Palette.ink)
                    Text("Pick an idea to get started.").font(.subheadline).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button {
                    chat.surprise()
                } label: {
                    Label("Surprise me", systemImage: "sparkle")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                ForEach(chat.suggestions) { suggestion in
                    Button {
                        // Fill the box; the child presses Ask. No keyboard:
                        // it only opens when the box itself is tapped.
                        chat.question = suggestion.question
                        focused = false
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(suggestion.icon)  \(suggestion.topic.uppercased())")
                                .font(.caption2.weight(.bold)).tracking(0.6)
                                .foregroundStyle(Palette.muted)
                            Text(suggestion.question)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                        .padding(12)
                        .background(Palette.card, in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Puts this question in the question box")
                }
            }
            Spacer(minLength: 0)
            Text("Made with love by **Ayaan and Naz**").font(.footnote).foregroundStyle(Palette.muted)
        }
    }
}

struct AnswerPanel: View {
    let chat: ChatModel
    let engines: [TutorEngine]
    @State private var speech = Speech()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("02 / FOLLOW YOUR CURIOSITY")
                    Text("Let’s discover.").font(.title2.bold()).foregroundStyle(Palette.ink)
                }
                Spacer()
                Image("BrandIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .clipShape(.rect(cornerRadius: 12))
                    .accessibilityHidden(true)
            }

            ScrollView {
                content.frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
            .frame(maxHeight: .infinity)

            if let reply = chat.reply, !chat.isLoading {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Keep exploring").font(.footnote.weight(.bold)).foregroundStyle(Palette.muted)
                    ForEach(reply.followUps, id: \.self) { followUp in
                        Button {
                            speech.stop()
                            chat.ask(followUp, using: engines)
                        } label: {
                            Text(followUp).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }

            Divider().overlay(Palette.line)
            HStack {
                Text(chat.status).font(.footnote).foregroundStyle(Palette.muted)
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer()
                Button {
                    if let answer = chat.reply?.answer { speech.toggle(answer) }
                } label: {
                    Label(speech.isSpeaking ? "Stop reading" : "Read aloud",
                          systemImage: speech.isSpeaking ? "stop.fill" : "speaker.wave.2")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(chat.reply == nil || chat.isLoading)
                .opacity(chat.reply == nil || chat.isLoading ? 0.5 : 1)
            }
        }
        .panel(fill: Palette.answerPanel)
        .onChange(of: chat.isLoading) { _, loading in if loading { speech.stop() } }
    }

    @ViewBuilder private var content: some View {
        if chat.isLoading {
            VStack(spacing: 10) {
                ProgressView().controlSize(.large).tint(Palette.accent)
                Text("Working on your answer…").font(.headline).foregroundStyle(Palette.ink)
                Text("The first question can take a little longer.").font(.footnote).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if let error = chat.errorText {
            Text(error)
                .foregroundStyle(Palette.errorText)
                .lineSpacing(4)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.errorBackground, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.errorLine))
        } else if let reply = chat.reply {
            VStack(alignment: .leading, spacing: 12) {
                Text(chat.askedQuestion).font(.headline).foregroundStyle(Palette.accent)
                Text(reply.answer).font(.body).lineSpacing(5).foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
            }
        } else {
            EmptyState()
        }
    }
}

/// The shared rocket-and-atom brand mark and welcome text.
struct EmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(.rect(cornerRadius: 28))
                .accessibilityHidden(true)
            Text("A little curiosity.\nA whole world to explore.")
                .font(.title3.weight(.semibold)).multilineTextAlignment(.center).foregroundStyle(Palette.ink)
            Text("Ask a question or choose an idea.\nYour science discovery starts here.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }
}

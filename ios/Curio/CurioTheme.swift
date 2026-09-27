import ScienceCore
import SwiftUI

/// Semantic colours (docs/DESIGN.md → Tokens). Each is a colour set in
/// Assets.xcassets/Colors with Any and Dark appearances, so it follows the
/// app's Light/Dark/System choice without code here.
enum Curio {
    static let ground = Color("Ground")
    static let surface = Color("Surface")
    static let border = Color("Border")
    static let ink = Color("Ink")
    static let muted = Color("Muted")
    static let label = Color("Label")
    static let placeholder = Color("Placeholder")
    /// Accent as a filled background (buttons, resume card, current step).
    static let accentFill = Color("AccentFill")
    /// Text and icons on `accentFill`.
    static let onAccent = Color("OnAccent")
    /// Accent as text and icons on the ground or a surface.
    static let accent = Color("AccentText")
    /// The current question's heading.
    static let accentHeading = Color("AccentHeading")
    static let accentTint = Color("AccentTint")
    static let connector = Color("Connector")
    static let upcomingConnector = Color("UpcomingConnector")
    static let upcoming = Color("Upcoming")
    static let locked = Color("Locked")
    static let success = Color("Success")
    static let heart = Color("Heart")
    /// Behind a category icon: white in light, a ground-coloured cut-out in dark.
    static let iconDisc = Color("IconDisc")
    /// Stars and dust in illustrations.
    static let sparkle = Color("Sparkle")
    /// The pixel field's four brightness levels (PixelField).
    static let fieldDim = Color("FieldDim")
    static let fieldMid = Color("FieldMid")
    static let fieldLit = Color("FieldLit")
    static let fieldCrest = Color("FieldCrest")
    static let danger = Color("Danger")
    static let dangerTint = Color("DangerTint")

    static let borderWidth = 1.5
    static let cardRadius = 20.0
    static let chipRadius = 14.0

    /// Fredoka, for headings. Falls back to the system font if not bundled.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold,
                        relativeTo style: Font.TextStyle = .title2) -> Font {
        .custom("Fredoka", size: size, relativeTo: style).weight(weight)
    }

    /// Nunito, for everything else. Falls back to the system font if not bundled.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .semibold,
                     relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Nunito", size: size, relativeTo: style).weight(weight)
    }
}

extension EnvironmentValues {
    /// At least 1100 pt wide (iPad landscape): two-column layouts from
    /// TabletHome/TabletTrail.dc.html. Narrower widths use the phone layout.
    @Entry var curioWide = false
}

/// A topic's tint, foreground colour, and icon. Weather, Animals, Space,
/// Sound, Light, and Body come from the design; the other bank topics'
/// colours are derived (marked in docs/DESIGN.md).
struct CategoryStyle {
    let fill: Color
    let foreground: Color
    let symbol: String

    private init(_ name: String, _ symbol: String) {
        fill = Color("\(name)Fill")
        foreground = Color("\(name)Ink")
        self.symbol = symbol
    }

    static func of(_ topic: String?) -> CategoryStyle {
        switch topic {
        case "Weather": CategoryStyle("Weather", "cloud.sun")
        case "Animals": CategoryStyle("Animals", "fish")
        case "Sound": CategoryStyle("Sound", "music.note")
        case "Light": CategoryStyle("Light", "lightbulb")
        case "Body": CategoryStyle("Body", "heart")
        case "Earth": CategoryStyle("Earth", "mountain.2")
        case "Electricity": CategoryStyle("Electricity", "bolt")
        case "Forces & motion": CategoryStyle("Forces", "move.3d")
        case "Matter": CategoryStyle("Matter", "atom")
        case "Plants": CategoryStyle("Plants", "leaf")
        default: CategoryStyle("Space", "moon.stars")  // and the child's own questions
        }
    }
}

/// White (surface) round button with the 1.5 px border, 44 pt by default.
struct CircleIconButton: View {
    let label: String
    let symbol: String
    var size = 44.0
    var tint = Curio.muted
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Curio.surface, in: .circle)
                .overlay(Circle().strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The bottom bar shared by Home and Trail: microphone (when this device
/// can recognise speech offline), question box, and send (or stop).
struct BottomBar: View {
    @Bindable var chat: ChatModel
    var focused: FocusState<Bool>.Binding
    let placeholder: String
    var voice: VoiceInput?
    /// Runs before listening starts (stops Read aloud).
    var beforeListening: () -> Void = {}
    let send: () -> Void

    private var canSend: Bool {
        !chat.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if let voice, voice.isAvailable {
                micButton(voice)
            }
            TextField("", text: $chat.question,
                      prompt: Text(placeholder).foregroundStyle(Curio.placeholder), axis: .vertical)
            .lineLimit(1...5)
            .font(Curio.body(16))
            .foregroundStyle(Curio.ink)
            .focused(focused)
            .submitLabel(.send)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .background(Curio.surface, in: .rect(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
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
                roundButton("Stop", symbol: "stop.fill", filled: true) { chat.cancel() }
            } else {
                roundButton("Ask", symbol: "arrow.up", filled: canSend, action: submit)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    /// Accent-filled when it can be used; otherwise the border colour with a
    /// muted icon (not a heavy grey disc).
    private func roundButton(_ label: String, symbol: String, filled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(filled ? Curio.onAccent : Curio.placeholder)
                .frame(width: 48, height: 48)
                .background(filled ? Curio.accentFill : Curio.border, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func submit() {
        voice?.stop()
        focused.wrappedValue = false
        send()
    }

    /// "Speak your question": the words appear in the box as the child talks.
    private func micButton(_ voice: VoiceInput) -> some View {
        Button {
            if voice.isListening {
                voice.stop()
            } else {
                beforeListening()
                focused.wrappedValue = false
                let before = chat.question.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    await voice.start { heard in
                        chat.question = before.isEmpty ? heard : "\(before) \(heard)"
                    }
                }
            }
        } label: {
            Image(systemName: voice.isListening ? "waveform" : "mic")
                .font(.system(size: 20, weight: .semibold))
                .symbolEffect(.variableColor.iterative, isActive: voice.isListening)
                .foregroundStyle(voice.isListening ? Curio.onAccent : Curio.accent)
                .frame(width: 48, height: 48)
                .background(voice.isListening ? Curio.accentFill : Curio.surface, in: .circle)
                .overlay(Circle().strokeBorder(voice.isListening ? .clear : Curio.border, lineWidth: Curio.borderWidth))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(chat.isLoading)
        .accessibilityLabel(voice.isListening ? "Stop listening" : "Speak your question")
    }
}

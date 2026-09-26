import ScienceCore
import SwiftUI
import UIKit

/// Design tokens from the 2026-09 redesign (docs/DESIGN.md → Tokens). The
/// light values are the design's; the dark values are derived (same hues on a
/// dark ground) and listed in the same table.
enum Curio {
    static let ground = Color(light: 0xFFF9F0, dark: 0x16142A)
    static let surface = Color(light: 0xFFFFFF, dark: 0x221F3A)
    static let border = Color(light: 0xEDE6DA, dark: 0x38345A)
    static let ink = Color(light: 0x211E3B, dark: 0xF3F0FF)
    static let muted = Color(light: 0x5B5775, dark: 0xBDB8D6)
    static let label = Color(light: 0x6B6785, dark: 0xA9A4C4)
    static let placeholder = Color(light: 0x7A7690, dark: 0x8E89A8)
    /// Accent as text and icons.
    static let accent = Color(light: 0x4F46C9, dark: 0xB8B0FF)
    /// Accent as a filled background under white text.
    static let accentFill = Color(light: 0x4F46C9, dark: 0x5E55D8)
    static let accentTint = Color(light: 0xE6E1FF, dark: 0x2B2650)
    static let connector = Color(light: 0xCFC8FF, dark: 0x4A4480)
    static let success = Color(light: 0x1F7A45, dark: 0x7FD6A0)
    static let locked = Color(light: 0xD6CFC2, dark: 0x4A4666)
    static let heart = Color(light: 0xE0554A, dark: 0xF07A70)

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

extension Color {
    /// A colour that follows Light/Dark, from 0xRRGGBB values.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

/// A topic's tint, foreground colour, and icon. The design defines Weather,
/// Animals, Space, and Sound; the other six bank topics are derived.
struct CategoryStyle {
    let fill: Color
    let foreground: Color
    let symbol: String

    static func of(_ topic: String?) -> CategoryStyle {
        switch topic {
        case "Weather":
            CategoryStyle(fill: Color(light: 0xDCEBFB, dark: 0x1B2B42), foreground: Color(light: 0x1D5FA8, dark: 0x8CC0F5), symbol: "cloud.sun")
        case "Animals":
            CategoryStyle(fill: Color(light: 0xDBF3E3, dark: 0x173426), foreground: Color(light: 0x1F7A45, dark: 0x7FD6A0), symbol: "fish")
        case "Sound":
            CategoryStyle(fill: Color(light: 0xFFE3D6, dark: 0x3E2219), foreground: Color(light: 0xB8452E, dark: 0xF5A38C), symbol: "music.note")
        case "Earth":
            CategoryStyle(fill: Color(light: 0xF1E7D6, dark: 0x33291B), foreground: Color(light: 0x7A5424, dark: 0xE0B98A), symbol: "mountain.2")
        case "Electricity":
            CategoryStyle(fill: Color(light: 0xD9F2F1, dark: 0x163332), foreground: Color(light: 0x116B69, dark: 0x7AD6D2), symbol: "bolt")
        case "Forces & motion":
            CategoryStyle(fill: Color(light: 0xFCE1EC, dark: 0x3B1D2B), foreground: Color(light: 0xA3305F, dark: 0xF29BC0), symbol: "move.3d")
        case "Light":
            CategoryStyle(fill: Color(light: 0xFFF0C7, dark: 0x3A3016), foreground: Color(light: 0x855A00, dark: 0xF2C766), symbol: "sun.max")
        case "Matter":
            CategoryStyle(fill: Color(light: 0xEEE2F7, dark: 0x2F2140), foreground: Color(light: 0x77389F, dark: 0xD3A6F0), symbol: "atom")
        case "Plants":
            CategoryStyle(fill: Color(light: 0xE6F2D2, dark: 0x25321A), foreground: Color(light: 0x4A6E12, dark: 0xB5D986), symbol: "leaf")
        default:  // Space, and questions the child typed
            CategoryStyle(fill: Curio.accentTint, foreground: Curio.accent, symbol: "moon.stars")
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

/// The bottom bar shared by Home and Trail: question box and send (or stop).
/// The design's microphone is not built yet (speech-to-text is a new feature).
struct BottomBar: View {
    @Bindable var chat: ChatModel
    var focused: FocusState<Bool>.Binding
    let placeholder: String
    let send: () -> Void

    private var canSend: Bool {
        !chat.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
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
                .foregroundStyle(filled ? Color.white : Curio.placeholder)
                .frame(width: 48, height: 48)
                .background(filled ? Curio.accentFill : Curio.border, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func submit() {
        focused.wrappedValue = false
        send()
    }
}

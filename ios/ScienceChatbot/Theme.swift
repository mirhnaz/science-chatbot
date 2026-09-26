import SwiftUI

/// Colours copied from public/styles.css, with light and dark variants in
/// Assets.xcassets, so the iPad app looks like the web app in both themes.
enum Palette {
    static let background = Color("Background")
    static let panel = Color("Panel")
    static let answerPanel = Color("AnswerPanel")
    static let ink = Color("Ink")
    static let muted = Color("Muted")
    static let line = Color("Line")
    static let input = Color("Input")
    static let card = Color("Card")
    static let accent = Color("Accent")
    static let accentSoft = Color("AccentSoft")
    static let primaryButton = Color("PrimaryButton")
    static let errorBackground = Color("ErrorBackground")
    static let errorText = Color("ErrorText")
    static let errorLine = Color("ErrorLine")
}

/// The web app's small spaced capitals above each panel title.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(Palette.muted)
    }
}

/// Rounded, bordered panel like `.panel` on the web.
struct PanelBackground: ViewModifier {
    var fill = Palette.panel

    func body(content: Content) -> some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(fill, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.line))
    }
}

/// Card-coloured bordered button, like `.secondary` on the web.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)  // HIG minimum touch target
            .background(configuration.isPressed ? Palette.accentSoft : Palette.card, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
    }
}

extension View {
    func panel(fill: Color = Palette.panel) -> some View { modifier(PanelBackground(fill: fill)) }
}

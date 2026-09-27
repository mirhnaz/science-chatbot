import SwiftUI

/// First launch only: "Hi! I'm Curio", an optional first name (kept on this
/// device), what sparks, trails and stamps are, and "Let's explore!".
/// ContentView shows it unless there is already a name, stamp or saved trail.
struct WelcomeView: View {
    let done: () -> Void
    @AppStorage("childName") private var childName = ""
    @State private var name = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BrandMark(size: 72)
                    .frame(maxWidth: .infinity)
                Text("Hi! I’m Curio")
                    .font(Curio.display(32, .bold, relativeTo: .largeTitle))
                    .foregroundStyle(Curio.ink)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 20)
                Text("Your science explorer. Let’s find out how the world works!")
                    .font(Curio.body(17))
                    .foregroundStyle(Curio.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                Text("What’s your first name?")
                    .font(Curio.body(15, .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Curio.ink)
                    .padding(.top, 28)
                TextField("", text: $name, prompt: Text("Your first name").foregroundStyle(Curio.placeholder))
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .font(Curio.body(17))
                    .foregroundStyle(Curio.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 52)
                    .background(Curio.surface, in: .capsule)
                    .overlay(Capsule().strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
                    .padding(.top, 8)
                    .onChange(of: name) { _, text in
                        if text.count > 40 { name = String(text.prefix(40)) }
                    }
                Text("So I can say hello. It stays on this device.")
                    .font(Curio.body(13))
                    .foregroundStyle(Curio.label)
                    .padding(.top, 6)

                VStack(spacing: 10) {
                    row("sparkles", "Sparks", "Tap a spark to ask a big question.")
                    row("point.topleft.down.to.point.bottomright.curvepath", "Trails", "Follow 5 steps to explore it deeper.")
                    row("seal", "Stamps", "Finish a trail to collect a stamp.")
                }
                .padding(.top, 28)

                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { childName = trimmed }
                    done()
                } label: {
                    Text("Let’s explore!")
                        .font(Curio.body(17, .heavy, relativeTo: .headline))
                        .foregroundStyle(Curio.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Curio.accentFill, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .padding(.top, 28)
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 20)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .pixelFieldBackground(.starfield)
        .background(Curio.ground)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Curio.accent)
                .frame(width: 40, height: 40)
                .background(Curio.accentTint, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Curio.display(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Curio.ink)
                Text(detail)
                    .font(Curio.body(14, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Curio.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Curio.surface, in: .rect(cornerRadius: Curio.chipRadius))
        .overlay(RoundedRectangle(cornerRadius: Curio.chipRadius).strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
        .accessibilityElement(children: .combine)
    }
}

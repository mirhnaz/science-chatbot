import ScienceCore
import SwiftUI

/// Home (docs/design/redesign-2026-09/Main.dc.html): a greeting, the trail to
/// pick up again, and four Sparks. No hero, so the Sparks stay above the fold
/// on small phones. The bottom bar is added by ContentView.
struct HomeView: View {
    let chat: ChatModel
    let resume: () -> Void
    let start: (Suggestion) -> Void
    let edit: (String) -> Void
    let openSettings: () -> Void
    @AppStorage("childName") private var name = ""

    private var greeting: String {
        let first = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return first.isEmpty ? "What are you curious about today?" : "What are you curious about today, \(first)?"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text(greeting)
                    .font(Curio.display(27, .bold, relativeTo: .largeTitle))
                    .foregroundStyle(Curio.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 18)
                if chat.hasUnfinishedTrail {
                    ResumeCard(chat: chat, resume: resume)
                        .padding(.top, 18)
                }
                SparksGrid(chat: chat, start: start, edit: edit)
                    .padding(.top, 22)
                MadeWithLove()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Curio.ground)
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 36)
            Text("Curio")
                .font(Curio.display(22, .bold, relativeTo: .title2))
                .tracking(0.22)
                .foregroundStyle(Curio.ink)
            Spacer()
            CircleIconButton(label: "Settings", symbol: "gearshape", action: openSettings)
        }
        .frame(minHeight: 44)
    }
}

/// "Continue your trail": shown only while a trail is unfinished.
struct ResumeCard: View {
    let chat: ChatModel
    let resume: () -> Void

    private var current: Int { chat.steps.count }

    var body: some View {
        Button(action: resume) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Continue your trail")
                    .textCase(.uppercase)
                    .font(Curio.body(12, .heavy, relativeTo: .caption))
                    .tracking(0.96)
                    .opacity(0.85)
                Text(chat.steps.first?.question ?? "")
                    .font(Curio.display(18, .semibold, relativeTo: .headline))
                    .multilineTextAlignment(.leading)
                HStack(spacing: 12) {
                    ProgressDots(done: chat.answeredSteps, total: ChatModel.trailLength)
                    // The design's short step label ("The nucleus") needs the
                    // tutor to name each step; until then, the step's question.
                    Text("Step \(current) · \(chat.steps.last?.question ?? "")")
                        .font(Curio.body(13, .bold, relativeTo: .footnote))
                        .lineLimit(1)
                        .opacity(0.9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        Text("Keep going")
                        Image(systemName: "chevron.right").fontWeight(.bold)
                    }
                    .font(Curio.body(14, .heavy, relativeTo: .subheadline))
                }
                .padding(.top, 2)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Curio.accentFill, in: .rect(cornerRadius: Curio.cardRadius))
            .contentShape(.rect(cornerRadius: Curio.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Continue your trail: \(chat.steps.first?.question ?? ""). Step \(current) of \(ChatModel.trailLength).")
        .accessibilityHint("Opens the trail where you left off")
        .accessibilityAddTraits(.isButton)
    }
}

/// Filled dots for answered steps, outlined for the rest.
struct ProgressDots: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                if index < done {
                    Circle().fill(.white).frame(width: 9, height: 9)
                } else {
                    Circle().strokeBorder(.white, lineWidth: 2).frame(width: 9, height: 9).opacity(0.6)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// "Sparks" with Shuffle, then a grid of tinted cards: two across on phones,
/// four on iPad. The whole card asks its question.
struct SparksGrid: View {
    let chat: ChatModel
    let start: (Suggestion) -> Void
    let edit: (String) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12),
                            count: sizeClass == .compact ? 2 : 4)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sparks")
                    .font(Curio.display(20, .bold, relativeTo: .title3))
                    .foregroundStyle(Curio.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { chat.surprise() } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(Curio.body(14, .heavy, relativeTo: .subheadline))
                        .foregroundStyle(Curio.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Curio.surface, in: .capsule)
                        .overlay(Capsule().strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(chat.isLoading)
                .accessibilityHint("Shows four different sparks")
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(chat.suggestions) { idea in
                    SparkCard(idea: idea) { start(idea) }
                        .contextMenu {
                            Button("Edit before asking", systemImage: "pencil") { edit(idea.question) }
                        }
                }
            }
        }
    }
}

struct SparkCard: View {
    let idea: Suggestion
    let action: () -> Void

    var body: some View {
        let style = CategoryStyle.of(idea.topic)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: style.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(style.foreground)
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: .circle)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(idea.topic)
                        .textCase(.uppercase)
                        .font(Curio.body(11, .heavy, relativeTo: .caption2))
                        .tracking(0.88)
                        .foregroundStyle(style.foreground)
                    Text(idea.question)
                        .font(Curio.body(15, .bold, relativeTo: .subheadline))
                        .foregroundStyle(Curio.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            // A minimum, not a fixed height, so larger text sizes still fit.
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(style.fill, in: .rect(cornerRadius: Curio.cardRadius))
            .contentShape(.rect(cornerRadius: Curio.cardRadius))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(idea.topic): \(idea.question)")
        .accessibilityHint("Starts a trail with this question")
        .accessibilityAddTraits(.isButton)
    }
}

/// "Made with love by Ayaan and Naz", with a heart icon instead of an emoji.
struct MadeWithLove: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill").foregroundStyle(Curio.heart).imageScale(.small)
            Text("Made with love by Ayaan and Naz")
        }
        .font(Curio.body(12, .bold, relativeTo: .caption))
        .foregroundStyle(Curio.label)
        .accessibilityElement(children: .combine)
    }
}

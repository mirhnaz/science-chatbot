import ScienceCore
import SwiftUI

/// Home (docs/design/redesign-2026-09/Main.dc.html; TabletHome when wide): a
/// greeting, the trail to pick up again, and four Sparks. No hero, so the
/// Sparks stay above the fold on small phones. ContentView adds the bottom bar.
struct HomeView: View {
    let chat: ChatModel
    let stamps: StampStore
    /// Opens an unfinished trail (the current one or an earlier one).
    let resume: (UUID) -> Void
    let start: (Suggestion) -> Void
    let edit: (String) -> Void
    let openSettings: () -> Void
    @AppStorage("childName") private var name = ""
    @Environment(\.curioWide) private var wide
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var greeting: String {
        let first = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hour = Calendar.current.component(.hour, from: .now)
        let when = hour >= 18 || hour < 5 ? "tonight" : "today"
        return first.isEmpty ? "What are you curious about \(when)?" : "What are you curious about \(when), \(first)?"
    }

    var body: some View {
        if wide { wideBody } else { phoneBody }
    }

    /// iPad landscape: a 380 pt column beside the Sparks.
    private var wideBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 40)
            ScrollView {
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(greeting)
                            .font(Curio.display(34, .bold, relativeTo: .largeTitle))
                            .foregroundStyle(Curio.ink)
                            .accessibilityAddTraits(.isHeader)
                        OpenTrails(trails: chat.openTrails, resume: resume)
                        if !stamps.trails.isEmpty {
                            FinishedTrailsCard(trails: stamps.trails)
                        }
                        MadeWithLove()
                    }
                    .frame(width: 380, alignment: .leading)
                    SparksGrid(chat: chat, start: start, edit: edit)
                }
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, 16)
        .pixelFieldBackground(fieldScene)
        .background(Curio.ground)
    }

    /// Stars and a comet on phones, an atom on iPad.
    private var fieldScene: PixelField.Scene { sizeClass == .compact ? .starfield : .atom }

    private var phoneBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text(greeting)
                    .font(Curio.display(27, .bold, relativeTo: .largeTitle))
                    .foregroundStyle(Curio.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 18)
                OpenTrails(trails: chat.openTrails, resume: resume)
                    .padding(.top, 18)
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
        .pixelFieldBackground(fieldScene)
        .background(Curio.ground)
    }

    private var header: some View {
        HStack(spacing: wide ? 12 : 10) {
            BrandMark(size: wide ? 40 : 36)
            Text("Curio")
                .font(Curio.display(wide ? 24 : 22, .bold, relativeTo: .title2))
                .tracking(0.22)
                .foregroundStyle(Curio.ink)
            Spacer()
            if !stamps.stamps.isEmpty {
                StampsBadge(count: stamps.stamps.count)
            }
            CircleIconButton(label: "Settings", symbol: "gearshape", action: openSettings)
        }
        .frame(minHeight: wide ? 48 : 44)
    }
}

/// "3 stamps", on every layout: a count only for now. (The design links it
/// to a Stamps screen, which does not exist yet.)
struct StampsBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.stars")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Curio.accent)
                .frame(width: 22, height: 22)
                .background(Curio.accentTint, in: .circle)
            Text(count == 1 ? "1 stamp" : "\(count) stamps")
                .font(Curio.body(15, .heavy, relativeTo: .subheadline))
                .foregroundStyle(Curio.ink)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(Curio.surface, in: .capsule)
        .overlay(Capsule().strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
        .accessibilityElement(children: .combine)
    }
}

/// "Trails you finished": the latest three, newest first (topic and first
/// question, kept on this device).
struct FinishedTrailsCard: View {
    let trails: [FinishedTrail]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trails you finished")
                    .font(Curio.display(16, .semibold, relativeTo: .headline))
                    .foregroundStyle(Curio.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(trails.count)")
                    .font(Curio.body(13, .heavy, relativeTo: .footnote))
                    .foregroundStyle(Curio.label)
            }
            ForEach(trails.suffix(3).reversed()) { trail in
                let style = CategoryStyle.of(trail.topic)
                HStack(spacing: 10) {
                    Image(systemName: style.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(style.foreground)
                        .frame(width: 32, height: 32)
                        .background(style.fill, in: .circle)
                    Text(trail.question)
                        .font(Curio.body(14, .bold, relativeTo: .subheadline))
                        .foregroundStyle(Curio.muted)
                }
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Curio.surface, in: .rect(cornerRadius: Curio.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Curio.cardRadius).strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
    }
}

/// Unfinished trails (up to three, newest first): the newest as the big
/// "Continue your trail" card, earlier ones as small rows under it.
struct OpenTrails: View {
    let trails: [TrailSummary]
    let resume: (UUID) -> Void

    var body: some View {
        if let newest = trails.first {
            VStack(alignment: .leading, spacing: 10) {
                ResumeCard(trail: newest) { resume(newest.id) }
                ForEach(trails.dropFirst()) { trail in
                    EarlierTrailRow(trail: trail) { resume(trail.id) }
                }
            }
        }
    }
}

/// An earlier unfinished trail: topic icon, first question, progress.
struct EarlierTrailRow: View {
    let trail: TrailSummary
    let resume: () -> Void

    var body: some View {
        let style = CategoryStyle.of(trail.topic)
        Button(action: resume) {
            HStack(spacing: 12) {
                Image(systemName: style.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(style.foreground)
                    .frame(width: 36, height: 36)
                    .background(style.fill, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trail.question)
                        .font(Curio.body(15, .bold, relativeTo: .subheadline))
                        .foregroundStyle(Curio.ink)
                        .lineLimit(1)
                    Text("Step \(trail.answered) of \(ChatModel.trailLength)")
                        .font(Curio.body(12, .bold, relativeTo: .caption))
                        .foregroundStyle(Curio.label)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Curio.accent)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(Curio.surface, in: .rect(cornerRadius: Curio.chipRadius))
            .overlay(RoundedRectangle(cornerRadius: Curio.chipRadius).strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
            .contentShape(.rect(cornerRadius: Curio.chipRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Earlier trail: \(trail.question). Step \(trail.answered) of \(ChatModel.trailLength).")
        .accessibilityHint("Opens this trail where you left off")
        .accessibilityAddTraits(.isButton)
    }
}

/// "Continue your trail": the newest unfinished trail.
struct ResumeCard: View {
    let trail: TrailSummary
    let resume: () -> Void
    @Environment(\.curioWide) private var wide

    var body: some View {
        Button(action: resume) {
            VStack(alignment: .leading, spacing: wide ? 12 : 8) {
                Text("Continue your trail")
                    .textCase(.uppercase)
                    .font(Curio.body(12, .heavy, relativeTo: .caption))
                    .tracking(0.96)
                    .opacity(0.85)
                Text(trail.question)
                    .font(Curio.display(wide ? 22 : 18, .semibold, relativeTo: .headline))
                    .multilineTextAlignment(.leading)
                HStack(spacing: 12) {
                    ProgressDots(done: trail.answered, total: ChatModel.trailLength)
                    // The tutor's label for the step ("The nucleus"), else its question.
                    Text("Step \(trail.answered) · \(trail.latest)")
                        .font(Curio.body(13, .bold, relativeTo: .footnote))
                        .lineLimit(1)
                        .opacity(0.9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !wide { keepGoing.font(Curio.body(14, .heavy, relativeTo: .subheadline)) }
                }
                .padding(.top, 2)
                if wide {
                    // iPad: a white button inside the card.
                    keepGoing
                        .font(Curio.body(16, .heavy, relativeTo: .headline))
                        .foregroundStyle(Curio.accentFill)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Curio.onAccent, in: .capsule)
                        .padding(.top, 4)
                }
            }
            .foregroundStyle(Curio.onAccent)
            .padding(.vertical, wide ? 22 : 16)
            .padding(.horizontal, wide ? 24 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Curio.accentFill, in: .rect(cornerRadius: wide ? 24 : Curio.cardRadius))
            .contentShape(.rect(cornerRadius: wide ? 24 : Curio.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Continue your trail: \(trail.question). Step \(trail.answered) of \(ChatModel.trailLength).")
        .accessibilityHint("Opens the trail where you left off")
        .accessibilityAddTraits(.isButton)
    }
}

extension ResumeCard {
    private var keepGoing: some View {
        HStack(spacing: 4) {
            Text("Keep going")
            Image(systemName: "chevron.right").fontWeight(.bold)
        }
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
                    Circle().fill(Curio.onAccent).frame(width: 9, height: 9)
                } else {
                    Circle().strokeBorder(Curio.onAccent, lineWidth: 2).frame(width: 9, height: 9).opacity(0.6)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// "Sparks" with Shuffle, then tinted cards: 2×2 on phones, 3×2 (six sparks)
/// when wide. The whole card asks its question.
struct SparksGrid: View {
    let chat: ChatModel
    let start: (Suggestion) -> Void
    let edit: (String) -> Void
    @Environment(\.curioWide) private var wide

    var body: some View {
        let gap = wide ? 16.0 : 12.0
        let columns = Array(repeating: GridItem(.flexible(), spacing: gap), count: wide ? 3 : 2)
        VStack(alignment: .leading, spacing: wide ? 14 : 12) {
            HStack {
                Text("Sparks")
                    .font(Curio.display(wide ? 22 : 20, .bold, relativeTo: .title3))
                    .foregroundStyle(Curio.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { chat.surprise() } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(Curio.body(14, .heavy, relativeTo: .subheadline))
                        .foregroundStyle(Curio.accent)
                        .padding(.horizontal, wide ? 16 : 14)
                        .frame(minHeight: wide ? 40 : 36)
                        .background(Curio.surface, in: .capsule)
                        .overlay(Capsule().strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows four different sparks")
            }
            LazyVGrid(columns: columns, spacing: gap) {
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
    @Environment(\.curioWide) private var wide

    var body: some View {
        let style = CategoryStyle.of(idea.topic)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: style.symbol)
                    .font(.system(size: wide ? 24 : 20, weight: .medium))
                    .foregroundStyle(style.foreground)
                    .frame(width: wide ? 48 : 40, height: wide ? 48 : 40)
                    .background(Curio.iconDisc, in: .circle)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: wide ? 4 : 3) {
                    Text(idea.topic)
                        .textCase(.uppercase)
                        .font(Curio.body(wide ? 12 : 11, .heavy, relativeTo: .caption2))
                        .tracking(0.88)
                        .foregroundStyle(style.foreground)
                    Text(idea.question)
                        .font(Curio.body(wide ? 17 : 15, .bold, relativeTo: .subheadline))
                        .foregroundStyle(Curio.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(wide ? 18 : 14)
            // A minimum, not a fixed height, so larger text sizes still fit.
            .frame(maxWidth: .infinity, minHeight: wide ? 186 : 148, alignment: .topLeading)
            .background(style.fill, in: .rect(cornerRadius: wide ? 22 : Curio.cardRadius))
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

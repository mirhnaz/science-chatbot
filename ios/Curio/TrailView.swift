import SwiftUI

/// Trail (docs/design/redesign-2026-09/Trail.dc.html): earlier steps as a
/// numbered rail, then the current step with an illustration, the answer, and
/// two "Dive deeper" choices directly under it. The bottom bar and header are
/// added by ContentView.
struct TrailView: View {
    let chat: ChatModel
    let speakingStep: UUID?
    let speak: (TrailStep) -> Void
    let dive: (String) -> Void
    let editFollowUp: (String) -> Void
    let retry: () -> Void
    let finish: () -> Void
    /// Earlier steps the child opened again from the rail.
    @State private var expanded: Set<UUID> = []
    @State private var position = ScrollPosition(idType: UUID.self)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(chat.steps.enumerated()), id: \.element.id) { index, step in
                    if step.id == chat.steps.last?.id {
                        CurrentStep(step: step, number: index + 1, topic: chat.topic,
                                    speaking: speakingStep == step.id, speak: { speak(step) },
                                    complete: chat.isComplete, dive: dive, editFollowUp: editFollowUp,
                                    retry: retry, finish: finish)
                    } else {
                        RailStep(step: step, number: index + 1, open: expanded.contains(step.id),
                                 speaking: speakingStep == step.id, speak: { speak(step) }) {
                            withAnimation(.smooth) {
                                if expanded.remove(step.id) == nil { expanded.insert(step.id) }
                            }
                        }
                        Capsule()
                            .fill(Curio.connector)
                            .frame(width: 2, height: 10)
                            .padding(.leading, 12)
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .background(Curio.ground)
        .scrollPosition($position)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .onChange(of: chat.steps.last?.id) { _, id in
            guard id != nil else { return }
            // Close re-opened steps, then show the rail and the new step from
            // the top. SwiftUI drops a scroll asked for while a layout
            // animation is running, so it waits for the fold to settle.
            let fold = reduceMotion ? 0.15 : 0.3
            withAnimation(.smooth(duration: fold)) { expanded = [] }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(fold + 0.05))
                withAnimation(trailAnimation(reduceMotion)) { position.scrollTo(edge: .top) }
            }
        }
    }
}

/// The animation for adding a step: a smooth glide, or a short fade-like
/// ease when Reduce Motion is on.
func trailAnimation(_ reduceMotion: Bool) -> Animation {
    reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.55)
}

/// Header: back · trail name and "Trail · Step N" · settings.
struct TrailHeader: View {
    let title: String
    let detail: String
    let back: () -> Void
    let settings: () -> Void

    var body: some View {
        HStack {
            CircleIconButton(label: "Back to home", symbol: "chevron.left", action: back)
            Spacer(minLength: 8)
            VStack(spacing: 1) {
                Text(title)
                    .font(Curio.display(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Curio.ink)
                    .lineLimit(1)
                Text(detail)
                    .textCase(.uppercase)
                    .font(Curio.body(12, .heavy, relativeTo: .caption))
                    .tracking(0.72)
                    .foregroundStyle(Curio.label)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            CircleIconButton(label: "Settings", symbol: "gearshape", action: settings)
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }
}

/// A numbered disc: tinted for earlier steps, filled for the current one.
struct StepNumber: View {
    let number: Int
    let current: Bool

    var body: some View {
        Text("\(number)")
            .font(Curio.body(13, .heavy, relativeTo: .footnote))
            .foregroundStyle(current ? Curio.onAccent : Curio.accent)
            .frame(width: 26, height: 26)
            .background(current ? Curio.accentFill : Curio.accentTint, in: .circle)
            .accessibilityHidden(true)
    }
}

/// An earlier step on the rail: number, one-line question, and a chevron.
/// Tapping shows its answer again.
struct RailStep: View {
    let step: TrailStep
    let number: Int
    let open: Bool
    let speaking: Bool
    let speak: () -> Void
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    StepNumber(number: number, current: false)
                    Text(step.question)
                        .font(Curio.body(14, .bold, relativeTo: .subheadline))
                        .foregroundStyle(Curio.muted)
                        .lineLimit(open ? nil : 1)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Curio.muted)
                }
                .frame(minHeight: 40)
                .padding(.trailing, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Step \(number): \(step.question)")
            .accessibilityHint(open ? "Hides this answer" : "Shows this answer again")

            if open, let reply = step.reply {
                HStack(alignment: .top, spacing: 12) {
                    Text(reply.answer)
                        .font(Curio.body(16, .semibold))
                        .lineSpacing(7)
                        .foregroundStyle(Curio.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SpeakButton(speaking: speaking, action: speak)
                }
                .padding(.leading, 38)
                .padding(.vertical, 6)
                .transition(.opacity)
            }
        }
    }
}

/// Read aloud: 44 pt, accent icon; the waves pulse while reading.
struct SpeakButton: View {
    let speaking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: speaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                .font(.system(size: 18, weight: .semibold))
                .symbolEffect(.variableColor.iterative, isActive: speaking)
                .foregroundStyle(Curio.accent)
                .frame(width: 44, height: 44)
                .background(Curio.surface, in: .circle)
                .overlay(Circle().strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speaking ? "Stop reading" : "Read this aloud")
    }
}

/// The current step: question as the heading, illustration, answer, and what
/// comes next (Dive deeper, or Finish on the last step).
struct CurrentStep: View {
    let step: TrailStep
    let number: Int
    let topic: String?
    let speaking: Bool
    let speak: () -> Void
    let complete: Bool
    let dive: (String) -> Void
    let editFollowUp: (String) -> Void
    let retry: () -> Void
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                StepNumber(number: number, current: true)
                    .padding(.top, 3)
                Text(step.question)
                    .font(Curio.display(24, .semibold, relativeTo: .title))
                    .lineSpacing(3)
                    .foregroundStyle(Curio.accentHeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                if step.reply != nil {
                    SpeakButton(speaking: speaking, action: speak)
                        .padding(.top, -6)
                }
            }

            if step.isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Working on your answer…")
                        .font(Curio.body(16))
                        .foregroundStyle(Curio.muted)
                }
                .padding(.vertical, 12)
            } else if let error = step.error {
                VStack(alignment: .leading, spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(Curio.body(16))
                        .foregroundStyle(Curio.danger)
                    Button(action: retry) {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .font(Curio.body(15, .heavy))
                            .foregroundStyle(Curio.accent)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Curio.surface, in: .capsule)
                            .overlay(Capsule().strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Curio.surface, in: .rect(cornerRadius: Curio.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Curio.cardRadius).strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
            } else if let reply = step.reply {
                CategoryIllustration(topic: topic)
                Text(reply.answer)
                    .font(Curio.body(17, .semibold))
                    .lineSpacing(9)  // 17 pt text on a 26 pt line
                    .foregroundStyle(Curio.ink)
                    .textSelection(.enabled)
                if complete {
                    FinishButton(action: finish)
                } else {
                    DiveDeeper(questions: Array(reply.followUps.prefix(2)), ask: dive, edit: editFollowUp)
                }
            }
        }
        .padding(.top, 2)
    }
}

/// The illustration slot. The design asks for one flat picture per step,
/// generated per topic; until that exists, each category has its own scene.
struct CategoryIllustration: View {
    let topic: String?

    var body: some View {
        let style = CategoryStyle.of(topic)
        ZStack {
            // A few fixed "sparkles", then the category icon on a white disc.
            Canvas { context, size in
                let dots: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.08, 0.18, 1.6), (0.22, 0.8, 1.6), (0.42, 0.14, 2), (0.6, 0.86, 1.6),
                    (0.34, 0.5, 1.3), (0.78, 0.22, 1.8), (0.9, 0.7, 1.4), (0.14, 0.52, 1.2),
                ]
                for (x, y, r) in dots {
                    let rect = CGRect(x: x * size.width - r, y: y * size.height - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Curio.sparkle.opacity(0.9)))
                }
            }
            Circle().fill(Curio.sparkle.opacity(0.35)).frame(width: 92, height: 92)
            Image(systemName: style.symbol)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(style.foreground)
                .frame(width: 64, height: 64)
                .background(Curio.iconDisc, in: .circle)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 124)
        .background(style.fill, in: .rect(cornerRadius: 18))
        .accessibilityHidden(true)
    }
}

/// "Dive deeper": two full-width choices under the answer.
struct DiveDeeper: View {
    let questions: [String]
    let ask: (String) -> Void
    let edit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dive deeper")
                .font(Curio.display(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(Curio.label)
                .accessibilityAddTraits(.isHeader)
            ForEach(questions, id: \.self) { question in
                Button { ask(question) } label: {
                    HStack(spacing: 10) {
                        Text(question)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").fontWeight(.bold)
                    }
                    .font(Curio.body(15, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Curio.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 48)
                    .background(Curio.surface, in: .rect(cornerRadius: Curio.chipRadius))
                    .overlay(RoundedRectangle(cornerRadius: Curio.chipRadius).strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
                    .contentShape(.rect(cornerRadius: Curio.chipRadius))
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .contextMenu {
                    Button("Edit before asking", systemImage: "pencil") { edit(question) }
                }
            }
        }
    }
}

/// Shown on the last step instead of Dive deeper: opens Trail complete.
struct FinishButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Finish your trail", systemImage: "flag.checkered")
                .font(Curio.body(17, .heavy, relativeTo: .headline))
                .foregroundStyle(Curio.onAccent)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Curio.accentFill, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows what you found out and your stamp")
    }
}

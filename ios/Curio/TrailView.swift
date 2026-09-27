import SwiftUI

/// Trail (docs/design/redesign-2026-09/Trail.dc.html; TabletTrail when wide):
/// earlier steps as a numbered rail, then the current step with an
/// illustration, the answer, and "Dive deeper" choices directly under it.
/// ContentView adds the bottom bar and, on phones, the header.
struct TrailView: View {
    let chat: ChatModel
    let speakingStep: UUID?
    let speak: (TrailStep) -> Void
    let dive: (String) -> Void
    let editFollowUp: (String) -> Void
    let retry: () -> Void
    let finish: () -> Void
    let back: () -> Void
    /// Earlier steps the child opened again from the rail.
    @State private var expanded: Set<UUID> = []
    @State private var position = ScrollPosition(idType: UUID.self)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.curioWide) private var wide
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Visible height of the steps' scroll view, for the pixel field.
    @State private var visibleHeight = 0.0

    var body: some View {
        if wide {
            HStack(spacing: 0) {
                SideRail(chat: chat, expanded: expanded, toggle: toggle, back: back)
                    .frame(width: 340)
                steps
            }
        } else {
            steps
        }
    }

    private func toggle(_ id: UUID) {
        withAnimation(.smooth) {
            if expanded.remove(id) == nil { expanded.insert(id) }
        }
    }

    private var steps: some View {
        ScrollView {
          VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(chat.steps.enumerated()), id: \.element.id) { index, step in
                    if step.id == chat.steps.last?.id {
                        CurrentStep(step: step, number: index + 1, topic: chat.topic,
                                    speaking: speakingStep == step.id, speak: { speak(step) },
                                    complete: chat.isComplete, dive: dive, editFollowUp: editFollowUp,
                                    retry: retry, finish: finish)
                    } else if !wide || expanded.contains(step.id) {
                        // Wide layouts list the steps in the side rail and
                        // show only the answers the child re-opened here.
                        RailStep(step: step, number: index + 1, open: expanded.contains(step.id),
                                 speaking: speakingStep == step.id, speak: { speak(step) }) {
                            toggle(step.id)
                        }
                        .padding(.bottom, wide ? 16 : 0)
                        if !wide {
                            Capsule()
                                .fill(Curio.connector)
                                .frame(width: 2, height: 10)
                                .padding(.leading, 12)
                        }
                    }
                }
            }
            .frame(maxWidth: wide ? .infinity : 680, alignment: .leading)
            .padding(.horizontal, wide ? 40 : 20)
            .padding(.top, wide ? 24 : 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            // A quieter pixel field in the space under the last step.
            PixelField(scene: sizeClass == .compact ? .starfield : .atom, intensity: 0.55)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
          .frame(minHeight: visibleHeight)
        }
        .measureVisibleHeight { visibleHeight = $0 }
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
    var size = 44.0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: speaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                .font(.system(size: 18, weight: .semibold))
                .symbolEffect(.variableColor.iterative, isActive: speaking)
                .foregroundStyle(Curio.accent)
                .frame(width: size, height: size)
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
    @Environment(\.curioWide) private var wide

    var body: some View {
        VStack(alignment: .leading, spacing: wide ? 22 : 14) {
            HStack(alignment: .top, spacing: wide ? 16 : 12) {
                if !wide {
                    StepNumber(number: number, current: true)
                        .padding(.top, 3)
                }
                Text(step.question)
                    .font(Curio.display(wide ? 34 : 24, .semibold, relativeTo: .title))
                    .lineSpacing(3)
                    .foregroundStyle(Curio.accentHeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                if step.reply != nil {
                    SpeakButton(speaking: speaking, size: wide ? 48 : 44, action: speak)
                        .padding(.top, wide ? 0 : -6)
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
                if wide {
                    // iPad: the picture beside the answer, three choices.
                    HStack(alignment: .top, spacing: 28) {
                        CategoryIllustration(topic: topic)
                            .frame(width: 360, height: 260)
                        answer(reply.answer)
                    }
                } else {
                    CategoryIllustration(topic: topic)
                    answer(reply.answer)
                }
                if complete {
                    FinishButton(action: finish)
                        .frame(maxWidth: wide ? 360 : .infinity)
                } else {
                    DiveDeeper(questions: Array(reply.followUps.prefix(wide ? 3 : 2)), ask: dive, edit: editFollowUp)
                        .padding(.top, wide ? 4 : 0)
                }
            }
        }
        .padding(.top, 2)
    }

    /// 17/26 on phones, 20/32 when wide.
    private func answer(_ text: String) -> some View {
        Text(text)
            .font(Curio.body(wide ? 20 : 17, .semibold))
            .lineSpacing(wide ? 12 : 9)
            .foregroundStyle(Curio.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The illustration slot. The design asks for one flat picture per step,
/// generated per topic; until that exists, each category has its own scene.
struct CategoryIllustration: View {
    let topic: String?
    @Environment(\.curioWide) private var wide
    @Environment(\.colorScheme) private var colorScheme

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
            Circle().fill(Curio.sparkle.opacity(colorScheme == .dark ? 0.12 : 0.5)).frame(width: 92, height: 92)
            Image(systemName: style.symbol)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(style.foreground)
                .frame(width: 64, height: 64)
                .background(Curio.iconDisc, in: .circle)
        }
        .frame(maxWidth: .infinity, minHeight: 124, maxHeight: wide ? .infinity : 124)
        .background(style.fill, in: .rect(cornerRadius: wide ? 22 : 18))
        .accessibilityHidden(true)
    }
}

/// "Dive deeper": two full-width choices under the answer.
struct DiveDeeper: View {
    let questions: [String]
    let ask: (String) -> Void
    let edit: (String) -> Void
    @Environment(\.curioWide) private var wide

    var body: some View {
        VStack(alignment: .leading, spacing: wide ? 10 : 8) {
            Text("Dive deeper")
                .font(Curio.display(wide ? 17 : 15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(Curio.label)
                .accessibilityAddTraits(.isHeader)
            if wide {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(questions, id: \.self, content: chip)
                }
            } else {
                ForEach(questions, id: \.self, content: chip)
            }
        }
    }

    private func chip(_ question: String) -> some View {
        Button { ask(question) } label: {
            HStack(spacing: 10) {
                Text(question)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").fontWeight(.bold)
            }
            .font(Curio.body(15, .bold, relativeTo: .subheadline))
            .foregroundStyle(Curio.accent)
            .padding(.horizontal, wide ? 16 : 14)
            .padding(.vertical, wide ? 12 : 10)
            .frame(maxHeight: .infinity)
            .frame(minHeight: wide ? 64 : 48)
            .background(Curio.surface, in: .rect(cornerRadius: wide ? 16 : Curio.chipRadius))
            .overlay(RoundedRectangle(cornerRadius: wide ? 16 : Curio.chipRadius).strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
            .contentShape(.rect(cornerRadius: wide ? 16 : Curio.chipRadius))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .contextMenu {
            Button("Edit before asking", systemImage: "pencil") { edit(question) }
        }
    }
}

/// iPad side rail (TabletTrail.dc.html): All sparks, the trail's identity,
/// every step (done, current, still to come) ending with its stamp, and
/// what the child knows so far.
struct SideRail: View {
    let chat: ChatModel
    let expanded: Set<UUID>
    let toggle: (UUID) -> Void
    let back: () -> Void

    var body: some View {
        let style = CategoryStyle.of(chat.topic)
        let current = chat.steps.count
        VStack(alignment: .leading, spacing: 18) {
            Button(action: back) {
                Label("All sparks", systemImage: "chevron.left")
                    .font(Curio.body(15, .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Curio.muted)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Image(systemName: style.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(style.foreground)
                    .frame(width: 48, height: 48)
                    .background(style.fill, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.trailName ?? "Your question")
                        .font(Curio.display(22, .semibold, relativeTo: .title2))
                        .foregroundStyle(Curio.ink)
                    Text("\(chat.topic.map { "\($0) trail" } ?? "Trail") · \(min(current, ChatModel.trailLength)) of \(ChatModel.trailLength)")
                        .textCase(.uppercase)
                        .font(Curio.body(12, .heavy, relativeTo: .caption))
                        .tracking(0.72)
                        .foregroundStyle(Curio.label)
                }
            }
            .accessibilityElement(children: .combine)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(1...(ChatModel.trailLength + 1), id: \.self) { number in
                        row(number, current: current)
                        if number <= ChatModel.trailLength {
                            Capsule()
                                .fill(number < current ? Curio.connector : Curio.upcomingConnector)
                                .frame(width: 2, height: 14)
                                .padding(.leading, 13)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            let known = chat.steps.dropLast().compactMap(\.reply).suffix(3).map(stepFact)
            if !known.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("So far you know")
                        .textCase(.uppercase)
                        .font(Curio.body(12, .heavy, relativeTo: .caption))
                        .tracking(0.72)
                        .foregroundStyle(Curio.label)
                    ForEach(Array(known.enumerated()), id: \.offset) { _, fact in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Curio.success)
                                .accessibilityHidden(true)
                            Text(fact)
                                .font(Curio.body(14, .bold, relativeTo: .footnote))
                                .foregroundStyle(Curio.ink)
                        }
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Curio.ground, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 24)
        .padding(.leading, 32)
        .padding(.trailing, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Curio.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Curio.border).frame(width: Curio.borderWidth)
        }
    }

    @ViewBuilder
    private func row(_ number: Int, current: Int) -> some View {
        if number <= current, number <= chat.steps.count {
            let step = chat.steps[number - 1]
            if number == current {
                HStack(alignment: .top, spacing: 12) {
                    StepNumber(number: number, current: true)
                    Text(step.question)
                        .font(Curio.body(15, .heavy, relativeTo: .subheadline))
                        .foregroundStyle(Curio.ink)
                        .padding(.top, 4)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Curio.accentTint, in: .rect(cornerRadius: 14))
                .padding(.leading, -12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(number), current: \(step.question)")
            } else {
                Button { toggle(step.id) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        StepNumber(number: number, current: false)
                        Text(step.question)
                            .font(Curio.body(15, .bold, relativeTo: .subheadline))
                            .foregroundStyle(Curio.muted)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Step \(number): \(step.question)")
                .accessibilityHint(expanded.contains(step.id) ? "Hides this answer" : "Shows this answer again")
            }
        } else {
            let label = number > ChatModel.trailLength
                ? (chat.trailName.map { "\($0) stamp" } ?? "Your stamp")
                : (number == current + 1 ? "Next step" : "Step \(number)")
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(Curio.locked, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 28, height: 28)
                Text(label)
                    .font(Curio.body(15, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Curio.upcoming)
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label), not reached yet")
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

import Foundation
import Observation
import ScienceCore
import SwiftUI

/// One stamp per completed trail. Only the topic and the date are kept, on
/// this device, in UserDefaults.
struct Stamp: Codable, Identifiable, Equatable {
    /// The trail that earned it, so a trail is only stamped once.
    let id: UUID
    /// Starter topic, or nil for a trail that began with the child's own question.
    let topic: String?
    let earned: Date
}

/// A finished trail, for "Trails you finished": its topic, first question,
/// and date only.
struct FinishedTrail: Codable, Identifiable, Equatable {
    let id: UUID
    let topic: String?
    let question: String
    let finished: Date
}

/// Stamps and finished trails, kept on this device (UserDefaults).
@MainActor @Observable
final class StampStore {
    private static let stampsKey = "stamps"
    private static let trailsKey = "finishedTrails"
    private(set) var stamps: [Stamp] = StampStore.load(stampsKey)
    private(set) var trails: [FinishedTrail] = StampStore.load(trailsKey)
    /// False for Debug test runs (`-autoAsk`), so they never add stamps to
    /// a child's real collection.
    private let persists: Bool

    init(persists: Bool = true) {
        self.persists = persists
    }

    /// Topics whose stamp is not collected yet, once there is at least one
    /// stamp (before that, every topic would be "new").
    var uncollectedTopics: Set<String> {
        guard !stamps.isEmpty else { return [] }
        let collected = Set(stamps.compactMap(\.topic))
        return Set(StampsView.kinds.compactMap { $0 }).subtracting(collected)
    }

    /// Adds the trail's stamp and records it as finished, once per trail.
    func award(trail: UUID, topic: String?, question: String) {
        if !stamps.contains(where: { $0.id == trail }) {
            stamps.append(Stamp(id: trail, topic: topic, earned: .now))
            if persists { Self.save(stamps, Self.stampsKey) }
        }
        if !trails.contains(where: { $0.id == trail }) {
            trails = Array((trails + [FinishedTrail(id: trail, topic: topic, question: question, finished: .now)]).suffix(100))
            if persists { Self.save(trails, Self.trailsKey) }
        }
    }

    /// Removes every finished trail and the stamps those trails earned (Debug
    /// `-removeFinishedTrails`, for clearing test runs). Stamps earned before
    /// finished trails were recorded have no trail entry and are kept.
    func removeFinishedTrails() {
        let ids = Set(trails.map(\.id))
        stamps.removeAll { ids.contains($0.id) }
        trails = []
        Self.save(stamps, Self.stampsKey)
        Self.save(trails, Self.trailsKey)
    }

    private static func load<T: Decodable>(_ key: String) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Trail complete (docs/design/redesign-2026-09/Complete.dc.html): the stamp,
/// three things the child found out, their latest stamps, and what next.
struct CompleteView: View {
    let chat: ChatModel
    let stamps: StampStore
    let close: () -> Void
    let newSpark: () -> Void
    @State private var shareImage: Image?
    /// The celebration: the stamp lands, a pixel burst plays behind it.
    @State private var landed = false
    @State private var bursting = false
    @State private var burstStarted = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Visible height, so the actions sit at the bottom when everything fits.
    @State private var visibleHeight = 0.0
    @Environment(\.displayScale) private var displayScale

    private var topicName: String { chat.trailName ?? "Your question" }
    private var stampName: String { chat.trailName.map { "\($0) stamp" } ?? "Curious Mind stamp" }

    var body: some View {
        let style = CategoryStyle.of(chat.topic)
        let facts = recapFacts(chat.steps)
        // One scroll view for everything: on a short screen (iPad landscape)
        // it scrolls from the top; when it fits, the actions sit at the bottom.
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    CircleIconButton(label: "Close", symbol: "xmark", action: close)
                    Spacer()
                    Text("\(topicName) · \(chat.steps.count) steps")
                        .textCase(.uppercase)
                        .font(Curio.body(12, .heavy, relativeTo: .caption))
                        .tracking(0.72)
                        .foregroundStyle(Curio.label)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.top, 8)

                VStack(spacing: 0) {
                    Image(systemName: stampSymbol(chat.topic))
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(style.foreground)
                        .frame(width: 156, height: 156)
                        .background(style.fill, in: .circle)
                        .overlay(Circle().strokeBorder(Curio.accentFill, lineWidth: 5))
                        .scaleEffect(landed ? 1 : 0.2)
                        .rotationEffect(.degrees(landed ? 0 : -18))
                        .opacity(landed ? 1 : 0)
                        .background {
                            if bursting {
                                // Rings and sparkles from the stamp's centre.
                                PixelField(scene: .burst, tap: .init(point: CGPoint(x: 210, y: 210), at: burstStarted))
                                    .frame(width: 420, height: 420)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel(stampName)
                        .padding(.top, 26)
                    Text("Trail complete!")
                        .font(Curio.display(30, .bold, relativeTo: .largeTitle))
                        .foregroundStyle(Curio.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 20)
                    Text("You earned the \(stampName). Here’s what you figured out:")
                        .font(Curio.body(16))
                        .foregroundStyle(Curio.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                        .padding(.top, 8)

                    RecapCard(facts: facts)
                        .padding(.top, 20)

                    StampsRow(stamps: stamps.stamps, current: chat.trailID)
                        .padding(.top, 22)
                }

                Spacer(minLength: 24)
                VStack(spacing: 10) {
                    Button(action: newSpark) {
                        Text("Start a new spark")
                            .font(Curio.body(17, .heavy, relativeTo: .headline))
                            .foregroundStyle(Curio.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Curio.accentFill, in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    if let shareImage {
                        // The recap picture, plus the trail's questions as text.
                        ShareLink(item: shareImage, message: Text(questionsText),
                        preview: SharePreview("What I found out about \(topicName)", image: shareImage)) {
                            Label("Show a grown-up", systemImage: "square.and.arrow.up")
                                .font(Curio.body(16, .heavy, relativeTo: .headline))
                                .foregroundStyle(Curio.accent)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Curio.surface, in: .capsule)
                                .overlay(Capsule().strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 16)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: visibleHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        // The scroll view's own size, not its content: cannot loop.
        .onGeometryChange(for: Double.self) { proxy in
            proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom
        } action: { visibleHeight = max($0, 0) }
        .background(Curio.ground)
        .task { renderShareImage(facts: facts) }
        .onAppear(perform: celebrate)
        .sensoryFeedback(.success, trigger: landed) { _, now in now }
    }

    /// The stamp lands with a spring and a burst plays for a few seconds;
    /// with Reduce Motion it simply appears.
    private func celebrate() {
        guard !landed else { return }
        guard !reduceMotion else { landed = true; return }
        burstStarted = .now
        bursting = true
        withAnimation(.spring(duration: 0.7, bounce: 0.45)) { landed = true }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            bursting = false
        }
    }

    private var questionsText: String {
        let list = chat.steps.enumerated().map { "\($0.offset + 1). \($0.element.question)" }
        return "What I explored on Curio (\(topicName)):\n" + list.joined(separator: "\n")
    }

    /// "Show a grown-up" shares the recap card as a picture (light colours,
    /// whatever the app's theme).
    private func renderShareImage(facts: [String]) {
        let card = VStack(alignment: .leading, spacing: 12) {
            Text("\(topicName): what I found out")
                .font(Curio.display(20, .bold))
                .foregroundStyle(Curio.ink)
            RecapCard(facts: facts)
        }
        .padding(20)
        .frame(width: 390)
        .background(Curio.ground)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = displayScale
        if let image = renderer.uiImage { shareImage = Image(uiImage: image) }
    }
}

/// Three things from the trail: the tutor's facts (or first sentences) from
/// the first, middle, and last answers.
func recapFacts(_ steps: [TrailStep]) -> [String] {
    let replies = steps.compactMap(\.reply)
    guard !replies.isEmpty else { return [] }
    let picks = replies.count <= 3
        ? Array(replies.indices)
        : [0, replies.count / 2, replies.count - 1]
    return picks.map { stepFact(replies[$0]) }
}

/// What a step taught: the tutor's fact, else the answer's first sentence.
func stepFact(_ reply: TutorReply) -> String {
    reply.fact ?? firstSentence(reply.answer)
}

func firstSentence(_ text: String) -> String {
    var sentence = ""
    text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, stop in
        sentence = substring ?? ""
        stop = true
    }
    let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? text : trimmed
}

struct RecapCard: View {
    let facts: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(facts, id: \.self) { fact in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Curio.success)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    Text(fact)
                        .font(Curio.body(15, .bold, relativeTo: .subheadline))
                        .lineSpacing(4)
                        .foregroundStyle(Curio.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Curio.surface, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
    }
}

/// The latest stamps, newest (just earned) filled with its colour, then a
/// dashed outline for the next one to earn. Stamps are unlimited, so the
/// counter is a total.
struct StampsRow: View {
    let stamps: [Stamp]
    let current: UUID
    private static let shown = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your stamps")
                    .font(Curio.display(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Curio.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(stamps.count == 1 ? "1 stamp" : "\(stamps.count) stamps")
                    .font(Curio.body(13, .heavy, relativeTo: .footnote))
                    .foregroundStyle(Curio.label)
            }
            HStack(spacing: 10) {
                ForEach(stamps.suffix(Self.shown)) { stamp in
                    let style = CategoryStyle.of(stamp.topic)
                    let new = stamp.id == current
                    Image(systemName: stampSymbol(stamp.topic))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(new ? Curio.onAccent : style.foreground)
                        .frame(width: 56, height: 56)
                        .background(new ? Curio.accentFill : style.fill, in: .circle)
                        .accessibilityLabel("\(stamp.topic ?? "Curious Mind") stamp, \(new ? "just earned" : "earned")")
                }
                Circle()
                    .strokeBorder(Curio.locked, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .frame(width: 56, height: 56)
                    .accessibilityLabel("Next stamp, not earned yet")
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

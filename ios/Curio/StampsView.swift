import SwiftUI

/// Stamps: every kind of stamp (the bank's 11 topics and Curious Mind for
/// trails that began with the child's own question), each earned with its
/// count or dashed as still to find, then the latest stamps with dates.
struct StampsView: View {
    let stamps: StampStore
    let back: () -> Void
    @Environment(\.curioWide) private var wide
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The kinds in order; nil is Curious Mind.
    static let kinds: [String?] = ["Space", "Animals", "Plants", "Weather", "Light", "Sound",
                                   "Electricity", "Earth", "Matter", "Forces & motion", "Body", nil]

    /// A stamp's kind: its topic if it is one of the kinds, else Curious Mind.
    static func kind(of topic: String?) -> String? {
        kinds.contains(topic) ? topic : nil
    }

    private var counts: [String?: Int] {
        Dictionary(grouping: stamps.stamps, by: { Self.kind(of: $0.topic) }).mapValues(\.count)
    }

    var body: some View {
        let counts = counts
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12),
                            count: wide ? 6 : sizeClass == .compact ? 3 : 4)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(kinds: counts.count)
                if stamps.stamps.isEmpty {
                    Text("Finish a trail to earn your first stamp!")
                        .font(Curio.body(16))
                        .foregroundStyle(Curio.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Self.kinds, id: \.self) { kind in
                        KindCell(kind: kind, count: counts[kind] ?? 0)
                    }
                }
                .padding(.top, 20)
                if !stamps.stamps.isEmpty {
                    Text("Latest stamps")
                        .font(Curio.display(17, .semibold, relativeTo: .headline))
                        .foregroundStyle(Curio.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 28)
                    VStack(spacing: 8) {
                        ForEach(stamps.stamps.suffix(10).reversed()) { stamp in
                            StampRow(stamp: stamp)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .frame(maxWidth: wide ? 960 : 720)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Curio.ground)
    }

    private func header(kinds: Int) -> some View {
        let total = stamps.stamps.count
        return HStack {
            CircleIconButton(label: "Back to home", symbol: "chevron.left", action: back)
            Spacer(minLength: 8)
            VStack(spacing: 1) {
                Text("Your stamps")
                    .font(Curio.display(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Curio.ink)
                Text("\(total == 1 ? "1 stamp" : "\(total) stamps") · \(kinds) of \(Self.kinds.count) kinds")
                    .textCase(.uppercase)
                    .font(Curio.body(12, .heavy, relativeTo: .caption))
                    .tracking(0.72)
                    .foregroundStyle(Curio.label)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Color.clear.frame(width: 44, height: 44)
        }
        .frame(minHeight: 44)
    }
}

/// A stamp's icon: its topic's, or sparkles for Curious Mind.
func stampSymbol(_ topic: String?) -> String {
    StampsView.kind(of: topic) == nil ? "sparkles" : CategoryStyle.of(topic).symbol
}

private struct KindCell: View {
    let kind: String?
    let count: Int

    var body: some View {
        let style = CategoryStyle.of(kind)
        let name = kind ?? "Curious Mind"
        VStack(spacing: 6) {
            Image(systemName: stampSymbol(kind))
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(count > 0 ? style.foreground : Curio.upcoming)
                .frame(width: 72, height: 72)
                .background(count > 0 ? style.fill : .clear, in: .circle)
                .overlay {
                    if count == 0 {
                        Circle().strokeBorder(Curio.locked, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                }
            Text(name)
                .font(Curio.body(13, .heavy, relativeTo: .footnote))
                .foregroundStyle(Curio.ink)
                .multilineTextAlignment(.center)
            Text(count > 0 ? "×\(count)" : "Not yet")
                .font(Curio.body(12, .bold, relativeTo: .caption))
                .foregroundStyle(count > 0 ? style.foreground : Curio.label)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count > 0 ? "\(name): \(count == 1 ? "1 stamp" : "\(count) stamps")" : "\(name): not earned yet")
    }
}

private struct StampRow: View {
    let stamp: Stamp

    var body: some View {
        let kind = StampsView.kind(of: stamp.topic)
        let style = CategoryStyle.of(kind)
        HStack(spacing: 12) {
            Image(systemName: stampSymbol(kind))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(style.foreground)
                .frame(width: 34, height: 34)
                .background(style.fill, in: .circle)
            Text("\(kind ?? "Curious Mind") stamp")
                .font(Curio.body(15, .bold, relativeTo: .subheadline))
                .foregroundStyle(Curio.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(stamp.earned.formatted(.dateTime.day().month(.abbreviated)))
                .font(Curio.body(13, .bold, relativeTo: .footnote))
                .foregroundStyle(Curio.label)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(Curio.surface, in: .rect(cornerRadius: Curio.chipRadius))
        .overlay(RoundedRectangle(cornerRadius: Curio.chipRadius).strokeBorder(Curio.border, lineWidth: Curio.borderWidth))
        .accessibilityElement(children: .combine)
    }
}

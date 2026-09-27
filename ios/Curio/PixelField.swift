import SwiftUI

/// The pixel field (docs/DESIGN.md → Pixel field): a science scene in pixels
/// over the bottom half of Home and Trail, down to the screen's bottom edge
/// behind the question bar, and behind their content (see
/// `pixelFieldBackground`). PixelField.metal draws every pixel on the GPU;
/// this view only passes the time (about 30 times a second), its size, and
/// hover and tap positions. It pauses when off screen or in the background,
/// and shows a still frame with Reduce Motion.
struct PixelField: View {
    enum Scene: Float {
        /// `burst` is the stamp celebration: rings and sparkles from `tap`.
        case starfield = 0, atom = 1, solarSystem = 2, burst = 3
    }

    let scene: Scene
    /// 1 on Home, quieter on Trail.
    var intensity = 1.0
    /// In this view's coordinates: the line background pixels start below
    /// (0: a gradient over the whole field) and the empty space the scene
    /// fits in (nil: centred in the field).
    var fill = 0.0
    var space: CGRect?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var started = Date.now
    @State private var onScreen = false
    @State private var size = CGSize.zero
    /// Hover and tap positions in this view's coordinates.
    var pointer = Touch()
    var tap = Touch()

    /// Where and when the pointer or a tap last touched the field.
    struct Touch {
        var point = CGPoint(x: -9999, y: -9999)
        var at = Date.distantPast
    }

    var body: some View {
        let paused = reduceMotion || !onScreen || phase != .active
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
            let now = context.date
            let time = reduceMotion ? 12 : now.timeIntervalSince(started)
            let age = { (touch: Touch) in reduceMotion ? 99 : now.timeIntervalSince(touch.at) }
            let rect = space ?? CGRect(x: 0, y: 12, width: size.width, height: max(0, size.height - 24))
            Rectangle()
                .fill(.white)
                .colorEffect(ShaderLibrary.pixelField(
                    .float2(size.width, size.height), .float(time), .float(scene.rawValue), .float(intensity),
                    .float3(pointer.point.x, pointer.point.y, age(pointer)),
                    .float3(tap.point.x, tap.point.y, age(tap)),
                    .float(fill),
                    .float4(rect.minX, rect.minY, rect.maxX, rect.maxY),
                    .color(Curio.fieldDim), .color(Curio.fieldMid), .color(Curio.fieldLit), .color(Curio.fieldCrest),
                    // Planets and electrons in topic colours; the sun and nucleus in Light's.
                    .color(CategoryStyle.of("Weather").foreground), .color(CategoryStyle.of("Sound").foreground),
                    .color(CategoryStyle.of("Light").foreground), .color(CategoryStyle.of("Animals").foreground)))
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Shows the pixel field over the bottom half of this view, down to the
    /// screen's bottom edge behind bottom bars, and behind its content.
    /// On iPad the scene sits in the empty space below content marked with
    /// `pixelFieldContent()` (the solar system on the left, the atom
    /// centred), with background pixels filling the rest; phones keep it
    /// centred with the content scrolling over it. Hover and taps on the
    /// view reach the field (content still gets them).
    func pixelFieldBackground(_ scene: PixelField.Scene, intensity: Double = 1) -> some View {
        modifier(PixelFieldBackground(scene: scene, intensity: intensity))
    }

    /// Marks the content the pixel field's scene must stay below.
    func pixelFieldContent() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: ContentBottom.self, value: proxy.frame(in: .global).maxY)
            }
        }
    }
}

/// The lowest marked content, in global coordinates.
private struct ContentBottom: PreferenceKey {
    static let defaultValue: Double? = nil
    static func reduce(value: inout Double?, nextValue: () -> Double?) {
        if let next = nextValue() { value = max(value ?? next, next) }
    }
}

private struct PixelFieldBackground: ViewModifier {
    let scene: PixelField.Scene
    let intensity: Double
    /// All in global coordinates: this view's safe area (its top and the
    /// question bar's top), the field, and the lowest marked content.
    @State private var safe = CGRect.zero
    @State private var top = 0.0
    @State private var field = CGRect.zero
    @State private var contentBottom: Double?
    @State private var pointer = PixelField.Touch()
    @State private var tap = PixelField.Touch()

    func body(content: Content) -> some View {
        // From global coordinates to the field's.
        let inField = { (point: CGPoint) in CGPoint(x: point.x - field.minX, y: point.y - field.minY) }
        let (fill, space) = placement()
        content
            .background {
                VStack(spacing: 0) {
                    // The field starts halfway down the safe area.
                    Color.clear.frame(height: max(0, safe.midY - top))
                    PixelField(scene: scene, intensity: intensity, fill: fill, space: space, pointer: pointer, tap: tap)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { field = $0 }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
            }
            .onGeometryChange(for: [CGFloat].self) { proxy in
                let frame = proxy.frame(in: .global), insets = proxy.safeAreaInsets
                return [frame.minY, frame.minX, frame.minY + insets.top, frame.width,
                        max(0, frame.height - insets.top - insets.bottom)]
            } action: { values in
                top = values[0]
                safe = CGRect(x: values[1], y: values[2], width: values[3], height: values[4])
            }
            .onPreferenceChange(ContentBottom.self) { bottom in
                MainActor.assumeIsolated { contentBottom = bottom }
            }
            .onContinuousHover(coordinateSpace: .global) { hover in
                if case .active(let point) = hover { pointer = .init(point: inField(point), at: .now) }
            }
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tapped in
                tap = .init(point: inField(tapped.location), at: .now)
                pointer = tap
            })
    }

    /// In the field's coordinates: where background pixels start and the
    /// empty space for the scene, between the content and the bar.
    private func placement() -> (Double, CGRect?) {
        let floor = safe.maxY - field.minY
        guard scene != .starfield, let contentBottom else {
            return (0, CGRect(x: 0, y: 12, width: field.width, height: max(0, floor - 24)))
        }
        let fill = max(1, min(contentBottom - field.minY + 16, floor - 16))
        let width = scene == .solarSystem ? field.width * 0.7 : field.width
        return (fill, CGRect(x: 0, y: fill + 8, width: width, height: max(0, floor - 12 - fill - 8)))
    }
}

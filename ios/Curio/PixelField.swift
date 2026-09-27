import SwiftUI

/// The pixel field (docs/DESIGN.md → Pixel field): a science scene in pixels
/// in a band over the bottom half of Home and Trail, behind their content (see
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
            Rectangle()
                .fill(.white)
                .colorEffect(ShaderLibrary.pixelField(
                    .float2(size.width, size.height), .float(time), .float(scene.rawValue), .float(intensity),
                    .float3(pointer.point.x, pointer.point.y, age(pointer)),
                    .float3(tap.point.x, tap.point.y, age(tap)),
                    // The scene is centred in the band.
                    .float3(size.width / 2, size.height / 2, max(0, size.height / 2 - 12)),
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
    /// Shows the pixel field in a band over the bottom half of this view,
    /// behind its content and above bottom bars, whatever the content is.
    /// Hover and taps on the view reach the field (content still gets them).
    func pixelFieldBackground(_ scene: PixelField.Scene, intensity: Double = 1) -> some View {
        modifier(PixelFieldBackground(scene: scene, intensity: intensity))
    }
}

private struct PixelFieldBackground: ViewModifier {
    let scene: PixelField.Scene
    let intensity: Double
    @State private var height = 0.0
    @State private var topInset = 0.0
    @State private var pointer = PixelField.Touch()
    @State private var tap = PixelField.Touch()

    /// The band's share of the view's height.
    private static let share = 0.5

    func body(content: Content) -> some View {
        let bandTop = topInset + height * (1 - Self.share)
        // From this view's coordinates to the band's.
        let inBand = { (point: CGPoint) in CGPoint(x: point.x, y: point.y - bandTop) }
        content
            .background(alignment: .bottom) {
                PixelField(scene: scene, intensity: intensity, pointer: pointer, tap: tap)
                    .frame(height: height * Self.share)
            }
            .onGeometryChange(for: [Double].self) { proxy in
                [proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom, proxy.safeAreaInsets.top]
            } action: { values in
                height = max(0, values[0])
                topInset = values[1]
            }
            .onContinuousHover(coordinateSpace: .local) { hover in
                if case .active(let point) = hover { pointer = .init(point: inBand(point), at: .now) }
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { tapped in
                tap = .init(point: inBand(tapped.location), at: .now)
                pointer = tap
            })
    }
}

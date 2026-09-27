import SwiftUI

/// The pixel field (docs/DESIGN.md → Pixel field): a science scene in pixels
/// that fills the empty space at the end of Home and Trail. PixelField.metal
/// draws every pixel on the GPU; this view only passes the time (about 30
/// times a second), its size, and hover and tap positions. It pauses when off
/// screen or in the background, and shows a still frame with Reduce Motion.
struct PixelField: View {
    enum Scene: Float {
        case starfield = 0, atom = 1, solarSystem = 2
    }

    let scene: Scene
    /// 1 on Home, quieter on Trail.
    var intensity = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var started = Date.now
    @State private var onScreen = false
    @State private var size = CGSize.zero
    @State private var pointer = Touch()
    @State private var tap = Touch()

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
                    // The scene fills this view, which is the empty gap.
                    .float3(size.width / 2, size.height / 2, max(0, size.height / 2 - 12)),
                    .color(Curio.fieldDim), .color(Curio.fieldMid), .color(Curio.fieldLit), .color(Curio.fieldCrest),
                    // Planets and electrons in topic colours; the sun and nucleus in Light's.
                    .color(CategoryStyle.of("Weather").foreground), .color(CategoryStyle.of("Sound").foreground),
                    .color(CategoryStyle.of("Light").foreground), .color(CategoryStyle.of("Animals").foreground)))
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onContinuousHover { hover in
            if case .active(let point) = hover { pointer = Touch(point: point, at: .now) }
        }
        .onTapGesture { point in
            tap = Touch(point: point, at: .now)
            pointer = tap
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .accessibilityHidden(true)
    }
}

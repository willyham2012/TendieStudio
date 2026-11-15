import Foundation
import CoreGraphics

/// One-tap motion starting points. They generate ordinary keyframes, so
/// everything stays fully editable on the timeline afterwards.
enum MotionPreset: String, CaseIterable, Identifiable {
    case float, sway, pulse, spin, orbit, bounce, drift, breathe
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .float: return "cloud"
        case .sway: return "metronome"
        case .pulse: return "heart"
        case .spin: return "arrow.triangle.2.circlepath"
        case .orbit: return "circle.dotted"
        case .bounce: return "basketball"
        case .drift: return "wind"
        case .breathe: return "lungs"
        }
    }
    var blurb: String {
        switch self {
        case .float: return "Gentle up-and-down hover"
        case .sway: return "Rocks side to side"
        case .pulse: return "Soft scale heartbeat"
        case .spin: return "Continuous 360° turn"
        case .orbit: return "Circles around its spot"
        case .bounce: return "Drops with a physical bounce"
        case .drift: return "Slow sideways glide"
        case .breathe: return "Fades in and out"
        }
    }

    func tracks(for layer: WallpaperLayer, duration d: Double) -> [Track] {
        let p = layer.position
        func kf(_ t: Double, _ v: [Double], _ e: Easing = .easeInOut) -> Keyframe { Keyframe(time: t * d, value: v, easing: e) }
        switch self {
        case .float:
            return [Track(property: .position, keyframes: [
                kf(0, [p.x, p.y]), kf(0.5, [p.x, p.y - 28]), kf(1, [p.x, p.y])])]
        case .sway:
            return [Track(property: .rotation, keyframes: [
                kf(0, [layer.rotation]), kf(0.25, [layer.rotation + 6]),
                kf(0.75, [layer.rotation - 6]), kf(1, [layer.rotation])])]
        case .pulse:
            return [Track(property: .scale, keyframes: [
                kf(0, [layer.scale]), kf(0.5, [layer.scale * 1.08]), kf(1, [layer.scale])])]
        case .spin:
            return [Track(property: .rotation, keyframes: [
                kf(0, [layer.rotation], .linear), kf(1, [layer.rotation + 360], .linear)])]
        case .orbit:
            let r = 40.0, steps = 12
            let ks = (0...steps).map { i -> Keyframe in
                let a = Double(i) / Double(steps) * 2 * .pi
                return kf(Double(i) / Double(steps), [p.x + r * cos(a), p.y + r * sin(a)], .linear)
            }
            return [Track(property: .position, keyframes: ks)]
        case .bounce:
            return [Track(property: .position, keyframes: [
                kf(0, [p.x, p.y - 160], .bounce), kf(0.6, [p.x, p.y], .easeInOut), kf(1, [p.x, p.y - 160], .easeIn)])]
        case .drift:
            return [Track(property: .position, keyframes: [
                kf(0, [p.x - 50, p.y]), kf(1, [p.x + 50, p.y])], loop: .pingPong)]
        case .breathe:
            return [Track(property: .opacity, keyframes: [
                kf(0, [layer.opacity]), kf(0.5, [layer.opacity * 0.35]), kf(1, [layer.opacity])])]
        }
    }
}

import Foundation

enum Easing: Codable, Equatable, Hashable {
    case linear, easeIn, easeOut, easeInOut
    case spring       // damped overshoot
    case bounce       // ease-out bounce (physics-inspired)
    case bezier(Double, Double, Double, Double)   // CSS-style cubic-bezier control points

    static let presets: [(String, Easing)] = [
        ("Linear", .linear), ("Ease in", .easeIn), ("Ease out", .easeOut),
        ("Ease in-out", .easeInOut), ("Spring", .spring), ("Bounce", .bounce),
    ]
    var title: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease in"
        case .easeOut: return "Ease out"
        case .easeInOut: return "Ease in-out"
        case .spring: return "Spring"
        case .bounce: return "Bounce"
        case .bezier: return "Custom"
        }
    }

    /// Maps linear progress 0...1 to eased progress (may overshoot for spring).
    func apply(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        switch self {
        case .linear: return x
        case .easeIn: return Easing.cubic(x, 0.42, 0, 1, 1)
        case .easeOut: return Easing.cubic(x, 0, 0, 0.58, 1)
        case .easeInOut: return Easing.cubic(x, 0.42, 0, 0.58, 1)
        case .bezier(let a, let b, let c, let d): return Easing.cubic(x, a, b, c, d)
        case .spring:
            if x >= 1 { return 1 }
            return 1 - exp(-5.5 * x) * cos(11 * x)
        case .bounce:
            let n = 7.5625, d = 2.75
            var t = x
            if t < 1 / d { return n * t * t }
            if t < 2 / d { t -= 1.5 / d; return n * t * t + 0.75 }
            if t < 2.5 / d { t -= 2.25 / d; return n * t * t + 0.9375 }
            t -= 2.625 / d; return n * t * t + 0.984375
        }
    }

    private static func cubic(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if x <= 0 { return 0 }; if x >= 1 { return 1 }
        func bez(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let m = 1 - t
            return 3 * m * m * t * a + 3 * m * t * t * b + t * t * t
        }
        // Solve bez_x(t) = x by bisection (robust, tiny cost).
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            let v = bez(t, x1, x2)
            if abs(v - x) < 1e-6 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return bez(t, y1, y2)
    }
}

import Foundation
import CoreGraphics

/// Evaluates tracks and bakes them into uniformly sampled value arrays.
/// The SAME baked samples feed the live preview (CAKeyframeAnimation) and the
/// exported CAML, so what you preview is what gets exported.
///
/// Why uniform sampling: every animation in real community wallpapers is a
/// CAKeyframeAnimation with linear calculationMode and evenly spaced values;
/// `keyTimes`/`timingFunctions` never appear in the samples we validated
/// against, so easing is baked into the values instead of relying on them.
enum AnimationBaker {
    static let samplesPerSecond = 30.0
    static let maxSamples = 900

    static func value(of track: Track, at time: Double) -> [Double]? {
        let ks = track.keyframes.sorted { $0.time < $1.time }
        guard let first = ks.first, let last = ks.last else { return nil }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        for i in 0..<(ks.count - 1) where time >= ks[i].time && time <= ks[i + 1].time {
            let a = ks[i], b = ks[i + 1]
            let span = b.time - a.time
            let u = span > 0 ? (time - a.time) / span : 1
            let e = a.easing.apply(u)
            return zip(a.value, b.value).map { $0 + ($1 - $0) * e }
        }
        return last.value
    }

    static func sampleCount(duration: Double) -> Int {
        min(maxSamples, max(2, Int((duration * samplesPerSecond).rounded(.up)))) + 1
    }

    /// Samples covering [0, duration] inclusive, evenly spaced.
    static func bake(_ track: Track, duration: Double) -> [[Double]] {
        let n = sampleCount(duration: duration)
        return (0..<n).compactMap { i in
            value(of: track, at: duration * Double(i) / Double(n - 1))
        }
    }

    struct State { var position: CGPoint; var rotation: Double; var scale: Double; var opacity: Double }

    static func state(of layer: WallpaperLayer, at time: Double) -> State {
        func v(_ p: AnimProperty) -> [Double]? { layer.track(p).flatMap { value(of: $0, at: time) } }
        let pos = v(.position)
        return State(
            position: pos.map { CGPoint(x: $0[0], y: $0[1]) } ?? layer.position,
            rotation: v(.rotation)?[0] ?? layer.rotation,
            scale: v(.scale)?[0] ?? layer.scale,
            opacity: v(.opacity)?[0] ?? layer.opacity)
    }

    /// Insert or replace a keyframe at `time` (snapped to 1/30 s).
    static func upsert(_ track: inout Track, time: Double, value: [Double], easing: Easing? = nil) {
        let t = (time * samplesPerSecond).rounded() / samplesPerSecond
        if let i = track.keyframes.firstIndex(where: { abs($0.time - t) < 0.5 / samplesPerSecond }) {
            track.keyframes[i].value = value
            if let easing { track.keyframes[i].easing = easing }
        } else {
            track.keyframes.append(Keyframe(time: t, value: value, easing: easing ?? .easeInOut))
            track.keyframes.sort { $0.time < $1.time }
        }
    }
}

import Foundation
import CoreGraphics

/// Platform-neutral description of what a layer looks like and how it moves.
/// Both the live preview (CALayer) and the CAML writer consume this, so the
/// two cannot drift apart.
struct ResolvedAnimation: Equatable {
    enum Kind { case point, real }
    var keyPath: String
    var kind: Kind
    var values: [[Double]]
    var autoreverses: Bool
    var duration: Double
}

struct ResolvedLayer: Equatable {
    var id: UUID
    var name: String
    var kind: LayerKind
    var assetName: String?
    var bounds: CGSize
    var position: CGPoint
    var rotationRadians: Double
    var opacity: Double
    var fill: RGBA
    var cornerRadius: Double
    var animations: [ResolvedAnimation]
}

enum LayerResolver {
    static func resolve(_ l: WallpaperLayer, duration: Double) -> ResolvedLayer {
        let hasScaleTrack = l.track(.scale).map { !$0.keyframes.isEmpty } ?? false
        let s0 = AnimationBaker.state(of: l, at: 0)
        // A static scale is baked into the bounds (no transform attribute needed);
        // an animated scale keeps bounds at the unscaled size and animates a multiplier.
        let bakedScale = hasScaleTrack ? 1.0 : l.scale
        let size = CGSize(width: l.size.width * bakedScale, height: l.size.height * bakedScale)
        var anims: [ResolvedAnimation] = []
        for t in l.tracks where t.keyframes.count >= 1 {
            let baked = AnimationBaker.bake(t, duration: duration)
            let rev = t.loop == .pingPong
            switch t.property {
            case .position:
                anims.append(.init(keyPath: "position", kind: .point, values: baked, autoreverses: rev, duration: duration))
            case .rotation:
                anims.append(.init(keyPath: "transform.rotation.z", kind: .real,
                                   values: baked.map { [$0[0] * .pi / 180] }, autoreverses: rev, duration: duration))
            case .scale:
                anims.append(.init(keyPath: "transform.scale", kind: .real, values: baked, autoreverses: rev, duration: duration))
            case .opacity:
                anims.append(.init(keyPath: "opacity", kind: .real, values: baked, autoreverses: rev, duration: duration))
            }
        }
        // Shapes carry their own alpha in opacity (CAML backgroundColor has 3 components).
        let alpha = l.kind == .image ? 1.0 : l.fill.a
        if alpha != 1 {
            for i in anims.indices where anims[i].keyPath == "opacity" {
                anims[i].values = anims[i].values.map { [$0[0] * alpha] }
            }
        }
        let corner = l.kind == .ellipse ? min(size.width, size.height) / 2 : l.cornerRadius * bakedScale
        return ResolvedLayer(
            id: l.id, name: l.name, kind: l.kind, assetName: l.assetName,
            bounds: size, position: s0.position,
            rotationRadians: s0.rotation * .pi / 180,
            opacity: s0.opacity * alpha, fill: l.fill, cornerRadius: corner, animations: anims)
    }

    /// Layers drawn in a plane, bottom to top, excluding hidden ones.
    static func layers(in plane: Plane, of project: WallpaperProject) -> [ResolvedLayer] {
        project.layers.filter { $0.plane == plane && !$0.isHidden }
            .map { resolve($0, duration: project.duration) }
    }
}

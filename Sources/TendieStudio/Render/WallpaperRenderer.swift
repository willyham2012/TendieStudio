import UIKit
import SwiftUI
import QuartzCore

/// Builds a real Core Animation layer tree from a project. Uses the same
/// ResolvedLayer/baked samples as the CAML exporter, so previews match exports.
enum WallpaperRenderer {
    private static let imageCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>(); c.countLimit = 40; c.totalCostLimit = 128 * 1024 * 1024; return c
    }()

    static func image(at url: URL) -> UIImage? {
        let key = url.path as NSString
        if let i = imageCache.object(forKey: key) { return i }
        guard let i = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache.setObject(i, forKey: key, cost: Int(i.size.width * i.size.height * 4))
        return i
    }

    static func buildTree(_ project: WallpaperProject, assetsDir: URL) -> CALayer {
        let root = CALayer()
        root.bounds = CGRect(origin: .zero, size: project.canvasSize)
        root.anchorPoint = .zero
        root.position = .zero
        root.masksToBounds = true
        root.backgroundColor = UIColor(project.background).cgColor
        for plane in Plane.allCases {
            for r in LayerResolver.layers(in: plane, of: project) {
                root.addSublayer(makeLayer(r, assetsDir: assetsDir))
            }
        }
        return root
    }

    static func makeLayer(_ r: ResolvedLayer, assetsDir: URL) -> CALayer {
        let l = CALayer()
        l.bounds = CGRect(origin: .zero, size: r.bounds)
        l.position = r.position
        l.opacity = Float(r.opacity)
        l.transform = CATransform3DMakeRotation(CGFloat(r.rotationRadians), 0, 0, 1)
        l.cornerRadius = CGFloat(r.cornerRadius)
        l.masksToBounds = r.cornerRadius > 0
        l.allowsEdgeAntialiasing = true
        if r.kind == .image, let n = r.assetName, let img = image(at: assetsDir.appendingPathComponent(n)) {
            l.contents = img.cgImage
            l.contentsGravity = .resize
            l.minificationFilter = .trilinear
        } else if r.kind != .image {
            l.backgroundColor = UIColor(r.fill).withAlphaComponent(1).cgColor
        }
        for a in r.animations {
            let k = CAKeyframeAnimation(keyPath: a.keyPath)
            k.values = a.values.map { v -> Any in
                a.kind == .point ? NSValue(cgPoint: CGPoint(x: v[0], y: v[1])) : NSNumber(value: v[0])
            }
            k.calculationMode = .linear
            k.duration = a.duration
            k.autoreverses = a.autoreverses
            k.repeatCount = .infinity
            k.beginTime = 1e-100
            k.isRemovedOnCompletion = false
            l.add(k, forKey: a.keyPath)
        }
        return l
    }

    static func thumbnail(_ project: WallpaperProject, assetsDir: URL, height: CGFloat = 480) -> UIImage {
        let tree = buildTree(project, assetsDir: assetsDir)
        let k = height / project.canvasHeight
        let size = CGSize(width: project.canvasWidth * k, height: height)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            ctx.cgContext.scaleBy(x: k, y: k)
            tree.render(in: ctx.cgContext)
        }
    }
}

extension UIColor {
    convenience init(_ c: RGBA) { self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
}
extension Color {
    init(_ c: RGBA) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a) }
}

/// Hosts the layer tree. Paused/scrubbing uses speed=0 + timeOffset (zero cost
/// while idle); playing lets Core Animation drive everything on the render
/// server, so the app does no per-frame work.
final class WallpaperPreviewUIView: UIView {
    private var tree: CALayer?
    private var lastProject: WallpaperProject?
    private var lastAssets: URL?
    private var lastBounds: CGSize = .zero
    private var lastPlaying = false
    private var lastTime = 0.0

    override init(frame: CGRect) { super.init(frame: frame); layer.masksToBounds = true; isUserInteractionEnabled = false }
    required init?(coder: NSCoder) { fatalError() }

    func update(project: WallpaperProject, assetsDir: URL, time: Double, playing: Bool) {
        lastTime = time
        let structural = project != lastProject || assetsDir != lastAssets || bounds.size != lastBounds
        if structural || playing != lastPlaying {
            if structural {
                tree?.removeFromSuperlayer()
                let t = WallpaperRenderer.buildTree(project, assetsDir: assetsDir)
                let k = bounds.width / max(1, project.canvasWidth)
                t.setAffineTransform(CGAffineTransform(scaleX: k, y: k))
                layer.addSublayer(t)
                tree = t
            }
            lastProject = project; lastAssets = assetsDir; lastBounds = bounds.size; lastPlaying = playing
            guard let t = tree else { return }
            if playing {
                t.timeOffset = time
                t.speed = 1
                t.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            } else {
                t.beginTime = 0
                t.speed = 0
                t.timeOffset = time
            }
        } else if !playing, let t = tree {
            t.timeOffset = time
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // SwiftUI can call update before the view has a size; rebuild once it does.
        if let p = lastProject, let a = lastAssets, bounds.size != lastBounds {
            update(project: p, assetsDir: a, time: lastTime, playing: lastPlaying)
        }
    }
}

struct WallpaperPreview: UIViewRepresentable {
    let project: WallpaperProject
    let assetsDir: URL
    var time: Double = 0
    var playing: Bool = false
    func makeUIView(context: Context) -> WallpaperPreviewUIView { WallpaperPreviewUIView() }
    func updateUIView(_ v: WallpaperPreviewUIView, context: Context) {
        v.update(project: project, assetsDir: assetsDir, time: time, playing: playing)
    }
}

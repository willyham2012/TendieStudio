import Foundation
import CoreGraphics

/// Coordinates: canvas points, origin top-left, y grows downward.
/// Verified against real community wallpapers: CAML positions are written
/// unconverted and render top-left/y-down on device (see Docs/FORMAT.md).

struct RGBA: Codable, Equatable, Hashable {
    var r: Double, g: Double, b: Double, a: Double
    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    static let black = RGBA(0, 0, 0)
    static let white = RGBA(1, 1, 1)
}

enum Plane: String, Codable, CaseIterable, Identifiable {
    case background, floating, foreground
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Name used in the .ca folder inside the .tendies (verified from real files).
    var caName: String { title }
}

enum LayerKind: String, Codable { case image, rectangle, ellipse }

enum AnimProperty: String, Codable, CaseIterable, Identifiable {
    case position, rotation, scale, opacity
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var componentCount: Int { self == .position ? 2 : 1 }
    var symbol: String {
        switch self {
        case .position: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rotation: return "rotate.right"
        case .scale: return "arrow.up.left.and.arrow.down.right"
        case .opacity: return "circle.lefthalf.filled"
        }
    }
}

enum LoopMode: String, Codable, CaseIterable, Identifiable {
    case repeatForever, pingPong
    var id: String { rawValue }
    var title: String { self == .repeatForever ? "Repeat" : "Ping-pong" }
}

struct Keyframe: Codable, Equatable, Identifiable {
    var id = UUID()
    var time: Double            // seconds, 0...project.duration
    var value: [Double]         // position: [x,y]; others: [v]. rotation in degrees (clockwise).
    var easing: Easing = .easeInOut   // easing of the segment that STARTS at this keyframe
}

struct Track: Codable, Equatable, Identifiable {
    var id = UUID()
    var property: AnimProperty
    var keyframes: [Keyframe]
    var loop: LoopMode = .repeatForever
}

struct WallpaperLayer: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var kind: LayerKind
    var assetName: String?              // file inside the project's assets folder
    var plane: Plane = .floating
    var position: CGPoint               // centre of the layer
    var size: CGSize                    // unscaled size
    var rotation: Double = 0            // degrees, clockwise
    var scale: Double = 1
    var opacity: Double = 1
    var fill: RGBA = RGBA(0.4, 0.5, 1)  // for shapes
    var cornerRadius: Double = 0
    var isHidden = false
    var isLocked = false
    var tracks: [Track] = []

    func track(_ p: AnimProperty) -> Track? { tracks.first { $0.property == p } }
}

struct DevicePreset: Identifiable, Hashable {
    let name: String; let width: Double; let height: Double
    var id: String { name }
    /// Logical point sizes. 14 Pro Max is 430x932 @3x.
    static let all: [DevicePreset] = [
        .init(name: "iPhone 14 Pro Max", width: 430, height: 932),
        .init(name: "iPhone 14 Pro / 15 / 16", width: 393, height: 852),
        .init(name: "iPhone 15 Pro Max / 16 Plus", width: 430, height: 932),
        .init(name: "iPhone 16 Pro Max / 17 Pro Max", width: 440, height: 956),
        .init(name: "iPhone 13 / 12", width: 390, height: 844),
    ]
    static let iPhone14ProMax = all[0]
}

struct WallpaperProject: Codable, Identifiable, Equatable {
    var schemaVersion = 1
    var id = UUID()
    var name: String
    var createdAt = Date()
    var modifiedAt = Date()
    var canvasWidth: Double = DevicePreset.iPhone14ProMax.width
    var canvasHeight: Double = DevicePreset.iPhone14ProMax.height
    var background = RGBA(0.05, 0.06, 0.12)
    /// Length of one loop in seconds.
    var duration: Double = 6
    var layers: [WallpaperLayer] = []   // bottom -> top within each plane
    var canvasSize: CGSize { CGSize(width: canvasWidth, height: canvasHeight) }

    static func blank(name: String = "Untitled") -> WallpaperProject { WallpaperProject(name: name) }
}

/// Lightweight listing record for the Library.
struct ProjectSummary: Identifiable, Equatable {
    var id: UUID
    var name: String
    var modifiedAt: Date
    var layerCount: Int
    var thumbnailURL: URL?
}

extension WallpaperLayer {
    /// Image layer sized to fit (or cover) the canvas, centred.
    static func image(name: String, assetName: String, pixelSize: CGSize, canvas: CGSize, cover: Bool) -> WallpaperLayer {
        let kx = canvas.width / max(1, pixelSize.width), ky = canvas.height / max(1, pixelSize.height)
        let k = cover ? max(kx, ky) : min(kx, ky, 1)
        return WallpaperLayer(name: name, kind: .image, assetName: assetName,
                              position: CGPoint(x: canvas.width / 2, y: canvas.height / 2),
                              size: CGSize(width: pixelSize.width * k, height: pixelSize.height * k))
    }
}

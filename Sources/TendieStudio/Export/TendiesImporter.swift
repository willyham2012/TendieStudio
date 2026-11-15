import Foundation
import CoreGraphics

/// Reads real community .tendies files.
/// - `inspect` gathers metadata for the Library.
/// - `makeProject` converts static layers into an editable project. It imports
///   image/colour layers with their positions, sizes, rotation and opacity. The
///   community files' own animations (state machines, frame sequences) are NOT
///   converted, and the result says so.
struct TendiesInfo {
    var layerCount: Int
    var animationCount: Int
    var imageCount: Int
    var canvas: CGSize
    var previewImageData: Data?
    var report: ValidationReport
}

enum TendiesImporter {
    static func inspect(_ data: Data) -> TendiesInfo? {
        guard let entries = try? ZipArchive.read(data) else { return nil }
        let report = TendiesValidator.validate(entries)
        var images = 0
        var preview: Data?
        for e in entries where e.path.lowercased().contains("/assets/") && !e.isDirectory {
            let l = e.path.lowercased()
            if l.hasSuffix(".png") || l.hasSuffix(".jpg") || l.hasSuffix(".jpeg") || l.hasSuffix(".webp") {
                images += 1
                if preview == nil || e.data.count > (preview?.count ?? 0), e.data.count < 3_000_000, l.hasSuffix(".png") || l.hasSuffix(".jpg") { preview = e.data }
            }
        }
        var canvas = CGSize(width: 390, height: 844)
        if let c = entries.first(where: { $0.path.hasSuffix("Floating-390w-844h@3x~iphone.ca/main.caml") }) {
            let layers = CAMLLayerParser.parse(c.data)
            if let r = layers.first(where: { $0.name == "Root Layer" }) { canvas = r.size }
        }
        return TendiesInfo(layerCount: report.layerCount, animationCount: report.animationCount,
                           imageCount: images, canvas: canvas, previewImageData: preview, report: report)
    }

    struct ImportedProject { var project: WallpaperProject; var assets: [String: Data]; var notes: [String] }

    static func makeProject(from data: Data, name: String) throws -> ImportedProject {
        let entries = try ZipArchive.read(data)
        var project = WallpaperProject.blank(name: name)
        var assets: [String: Data] = [:]
        var notes: [String] = []
        var animationsDropped = 0
        for plane in Plane.allCases {
            guard let caml = entries.first(where: { $0.path.hasSuffix("/" + TendiesExporter.caFolder(plane) + "/main.caml") }) else { continue }
            let base = String(caml.path.dropLast("main.caml".count))
            let parsed = CAMLLayerParser.parse(caml.data)
            if let root = parsed.first(where: { $0.name == "Root Layer" }) {
                project.canvasWidth = Double(root.size.width); project.canvasHeight = Double(root.size.height)
            }
            for p in parsed where p.name != "Root Layer" && p.name != "TendieStudio Root" && p.name != "CAPlayground Root Layer" {
                if p.name == "Background Color", p.imageSrc == nil, let c = p.backgroundColor { project.background = c; continue }
                animationsDropped += p.animationCount
                if let src = p.imageSrc {
                    guard let img = entries.first(where: { $0.path == base + src }) else { continue }
                    let ext = (src as NSString).pathExtension.lowercased()
                    guard ["png", "jpg", "jpeg"].contains(ext) else { notes.append("Skipped \(src) (\(ext) not supported for editing)."); continue }
                    let key = "imp_\(assets.count + 1)_\(UUID().uuidString.prefix(6)).\(ext)"
                    assets[key] = img.data
                    var l = WallpaperLayer(name: p.name, kind: .image, assetName: key, plane: plane, position: p.position, size: p.size)
                    l.rotation = p.rotationRadians * 180 / .pi; l.opacity = p.opacity
                    project.layers.append(l)
                } else if let c = p.backgroundColor, p.size.width > 0 {
                    var l = WallpaperLayer(name: p.name, kind: .rectangle, assetName: nil, plane: plane, position: p.position, size: p.size)
                    l.fill = c; l.rotation = p.rotationRadians * 180 / .pi; l.opacity = p.opacity
                    project.layers.append(l)
                }
            }
        }
        if project.layers.isEmpty { notes.append("No importable image or colour layers were found.") }
        if animationsDropped > 0 { notes.append("\(animationsDropped) animation(s) were not imported — re-animate in the Studio.") }
        return ImportedProject(project: project, assets: assets, notes: notes)
    }
}

struct ParsedCAMLLayer {
    var name = ""
    var size = CGSize.zero
    var position = CGPoint.zero
    var rotationRadians = 0.0
    var opacity = 1.0
    var imageSrc: String?
    var backgroundColor: RGBA?
    var animationCount = 0
}

/// Flat (non-recursive) extraction of layer attributes from CAML.
final class CAMLLayerParser: NSObject, XMLParserDelegate {
    private var layers: [ParsedCAMLLayer] = []
    private var stack: [Int] = []
    static func parse(_ data: Data) -> [ParsedCAMLLayer] {
        let c = CAMLLayerParser(); let p = XMLParser(data: data); p.delegate = c; _ = p.parse(); return c.layers
    }
    private static func nums(_ s: String?) -> [Double] { (s ?? "").split(separator: " ").compactMap { Double($0) } }
    func parser(_ parser: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch n {
        case "CALayer":
            var l = ParsedCAMLLayer()
            l.name = a["name"] ?? "Layer"
            let b = Self.nums(a["bounds"]); if b.count == 4 { l.size = CGSize(width: b[2], height: b[3]) }
            let p = Self.nums(a["position"]); if p.count == 2 { l.position = CGPoint(x: p[0], y: p[1]) }
            l.rotationRadians = Double(a["transform.rotation.z"] ?? "") ?? 0
            l.opacity = Double(a["opacity"] ?? "") ?? 1
            let c = Self.nums(a["backgroundColor"]); if c.count >= 3 { l.backgroundColor = RGBA(c[0], c[1], c[2]) }
            layers.append(l); stack.append(layers.count - 1)
        case "CGImage":
            if let i = stack.last, layers[i].imageSrc == nil, let s = a["src"] { layers[i].imageSrc = s }
        case "animation":
            if let i = stack.last { layers[i].animationCount += 1 }
        default: break
        }
    }
    func parser(_ parser: XMLParser, didEndElement n: String, namespaceURI: String?, qualifiedName: String?) {
        if n == "CALayer" { _ = stack.popLast() }
    }
}
